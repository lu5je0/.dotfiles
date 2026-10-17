local Block = require('lu5je0.ext.git.line-log.block')
local M = {}

local function parent(commit)
  return (commit.parents or ''):match('%x+')
end

local function trim(text)
  return ((text or ''):gsub('%s+$', ''))
end

local function parse_files(stdout)
  local fields = vim.split(stdout or '', '\0', { plain = true })
  local files, i = {}, 1
  while i < #fields do
    local status, path = fields[i], fields[i + 1]
    i = i + 2
    local old_path
    if status:match('^[RC]') then
      old_path, path = path, fields[i]
      i = i + 1
    end
    files[#files + 1] = { status = status:sub(1, 1), path = path, old_path = old_path }
  end
  return files
end

-- All writes go to a disposable bare repository and its own index. The real
-- repository is only an object alternate; no checkout, cherry-pick or staging.
function M.project(commits, repo_root)
  local temp = vim.fn.tempname() .. '-selected-net-diff'
  local git_dir = temp .. '/repo.git'
  local opts = { commit_count = #commits, net_diff = true }
  opts.cleanup = function()
    vim.fn.delete(temp, 'rf')
  end
  opts.prepare = function(run, done)
    vim.fn.mkdir(temp, 'p')
    local function fail(message, result)
      done(nil, message .. '\n' .. trim(result and result.stderr))
    end
    local function virtual(args, callback, stdin)
      local cmd = { 'git', '--git-dir=' .. git_dir }
      vim.list_extend(cmd, args)
      run(cmd, repo_root, callback, {
        stdin = stdin,
        env = { GIT_INDEX_FILE = temp .. '/index', GIT_OBJECT_DIRECTORY = git_dir .. '/objects' },
      })
    end
    local empty_tree, base_tree, head, tip
    local function finish()
      virtual({ 'write-tree' }, function(result)
        if result.code ~= 0 then
          fail('Cannot write combined tree', result)
          return
        end
        local new_tree = trim(result.stdout)
        virtual({ 'diff', '--no-ext-diff', '--name-status', '-z', '-M', '-C', base_tree, new_tree }, function(diff)
          if diff.code ~= 0 then
            fail('Cannot compare combined tree', diff)
            return
          end
          local entries = {}
          for _, file in ipairs(parse_files(diff.stdout)) do
            local entry = {
              hash = commits[1].short_hash .. '..' .. commits[#commits].short_hash,
              message = 'Merged selected commits',
              path = file.path,
              old_path = file.old_path or file.path,
              change_type = file.status,
            }
            if file.status ~= 'A' then
              entry.old_source = { repo_root = repo_root, git_dir = git_dir, rev = base_tree, path = entry.old_path }
            end
            if file.status ~= 'D' then
              entry.new_source = { repo_root = repo_root, git_dir = git_dir, rev = new_tree, path = file.path }
            end
            entries[#entries + 1] = entry
          end
          done(entries)
        end)
      end)
    end
    local apply_commit
    local function add_untracked(commit, index, next_commit)
      local file = commit.files[index]
      if not file then
        next_commit()
        return
      end
      if file.status ~= '??' then
        add_untracked(commit, index + 1, next_commit)
        return
      end
      local abs = repo_root .. '/' .. file.path
      local stat = vim.uv.fs_lstat(abs)
      if not stat then
        fail('Cannot read untracked file ' .. file.path)
        return
      end
      local args = stat.type == 'link' and { 'hash-object', '-w', '--stdin' } or { 'hash-object', '-w', '--', abs }
      local mode = stat.type == 'link' and '120000' or (bit.band(stat.mode, 73) ~= 0 and '100755' or '100644')
      virtual(args, function(result)
        if result.code ~= 0 then
          fail('Cannot read untracked file ' .. file.path, result)
          return
        end
        virtual({ 'update-index', '--add', '--cacheinfo', mode, trim(result.stdout), file.path }, function(updated)
          if updated.code ~= 0 then
            fail('Cannot combine untracked file ' .. file.path, updated)
            return
          end
          add_untracked(commit, index + 1, next_commit)
        end)
      end, stat.type == 'link' and vim.uv.fs_readlink(abs) or nil)
    end
    apply_commit = function(index)
      local commit = commits[index]
      if not commit then
        finish()
        return
      end
      local function next_commit()
        if commit.local_change then
          add_untracked(commit, 1, function()
            apply_commit(index + 1)
          end)
        else
          apply_commit(index + 1)
        end
      end
      -- Consecutive selections already have their exact resulting tree. This
      -- also avoids patch-context conflicts that cannot exist in that case.
      if not commit.local_change and parent(commit) == tip then
        virtual({ 'read-tree', commit.hash }, function(result)
          if result.code ~= 0 then
            fail('Cannot read ' .. commit.short_hash, result)
            return
          end
          tip = commit.hash
          next_commit()
        end)
        return
      end
      local args = { 'diff', '--binary', '--full-index', '--no-ext-diff', '--no-textconv', '--no-color' }
      local function apply(result)
        if result.code ~= 0 then
          fail('Cannot read patch ' .. commit.short_hash, result)
          return
        end
        if (result.stdout or '') == '' then
          next_commit()
          return
        end
        virtual({ 'apply', '--cached', '--3way', '--whitespace=nowarn' }, function(applied)
          if applied.code ~= 0 then
            fail('Cannot merge selected commits: conflict at ' .. commit.short_hash .. '. Include its dependencies or select a continuous range.', applied)
            return
          end
          tip = false -- The virtual result can differ from the original commit.
          next_commit()
        end, result.stdout)
      end
      if commit.local_change then
        local cmd = { 'git' }
        vim.list_extend(cmd, args)
        cmd[#cmd + 1] = head
        run(cmd, repo_root, apply)
      else
        args[#args + 1] = parent(commit) or empty_tree
        args[#args + 1] = commit.hash
        virtual(args, apply)
      end
    end
    run({ 'git', 'rev-parse', '--show-object-format' }, repo_root, function(format)
      if format.code ~= 0 then
        fail('Cannot read repository format', format)
        return
      end
      run({ 'git', 'init', '--bare', '-q', '--object-format=' .. trim(format.stdout), git_dir }, repo_root, function(init)
        if init.code ~= 0 then
          fail('Cannot initialize temporary repository', init)
          return
        end
        run({ 'git', 'rev-parse', '--path-format=absolute', '--git-path', 'objects' }, repo_root, function(objects)
          if objects.code ~= 0 then
            fail('Cannot locate repository objects', objects)
            return
          end
          vim.fn.writefile({ trim(objects.stdout) }, git_dir .. '/objects/info/alternates')
          run({ 'git', 'rev-parse', 'HEAD' }, repo_root, function(resolved)
            if resolved.code ~= 0 then
              fail('Cannot resolve HEAD', resolved)
              return
            end
            head = trim(resolved.stdout)
            virtual({ 'mktree' }, function(empty)
              if empty.code ~= 0 then
                fail('Cannot create empty tree', empty)
                return
              end
              empty_tree = trim(empty.stdout)
              tip = commits[1].local_change and head or parent(commits[1])
              virtual({ 'read-tree', tip or empty_tree }, function(read)
                if read.code ~= 0 then
                  fail('Cannot read selection base', read)
                  return
                end
                virtual({ 'write-tree' }, function(base)
                  if base.code ~= 0 then
                    fail('Cannot read selection base tree', base)
                    return
                  end
                  base_tree = trim(base.stdout)
                  apply_commit(1)
                end)
              end)
            end, '')
          end)
        end)
      end)
    end)
  end
  return opts
end

local function content(block)
  return block and block:get_content() or {}
end

-- A line-history selection is one tracked block, whose paths may change.
-- Three-way merge a skipped revision only when its selected patch applies.
function M.blocks(entries)
  local temp = vim.fn.tempname() .. '-selected-block-diff'
  local opts = { commit_count = #entries, net_diff = true }
  opts.cleanup = function()
    vim.fn.delete(temp, 'rf')
  end
  opts.prepare = function(run, done)
    local first, last = entries[1], entries[#entries]
    local current = content(first.old_block)
    local function finish()
      if vim.deep_equal(content(first.old_block), current) and first.old_path == last.path then
        done {}
        return
      end
      local start = last.new_block and last.new_block.start_line or 1
      local lines = {}
      for i = 1, start - 1 do
        lines[i] = last.new_block.lines[i] or ''
      end
      vim.list_extend(lines, current)
      done {
        {
          hash = first.hash .. '..' .. last.hash,
          message = 'Merged selected commits',
          old_path = first.old_path,
          path = last.path,
          old_block = first.old_block,
          new_block = Block.new(lines, start, start + #current - 1),
          loaded = true,
        },
      }
    end
    local function step(index)
      local entry = entries[index]
      if not entry then
        finish()
        return
      end
      local old, new = content(entry.old_block), content(entry.new_block)
      if vim.deep_equal(current, old) then
        current = new
        step(index + 1)
        return
      end
      vim.fn.mkdir(temp, 'p')
      for name, values in pairs { ours = current, base = old, theirs = new } do
        vim.fn.writefile(values, temp .. '/' .. name)
      end
      run({ 'git', 'merge-file', '-p', temp .. '/ours', temp .. '/base', temp .. '/theirs' }, temp, function(result)
        if result.code ~= 0 then
          done(nil, 'Cannot merge selected commits: conflict at ' .. entry.hash .. '\n' .. trim(result.stderr))
          return
        end
        current = vim.split(result.stdout or '', '\n', { plain = true })
        if current[#current] == '' then
          table.remove(current)
        end
        vim.schedule(function()
          step(index + 1)
        end)
      end)
    end
    step(1)
  end
  return opts
end

return M
