-- Sidebar git_changes parser tests: tree-builder + git_root cache.
-- Usage: cd vim && nvim --headless -u NONE -l tests/sidebar/parser_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local parser = require('lu5je0.ext.sidebar.sources.git_changes.parser')

-- Tests need a stable cwd to compute abs_path; pin it to a tmp dir.
-- The helper creates the target dir if missing so callers don't have
-- to remember to mkdir before lcd.
local function with_cwd(target, fn)
  local prev = vim.fn.getcwd()
  if vim.fn.isdirectory(target) ~= 1 then
    vim.fn.mkdir(target, 'p')
  end
  vim.cmd('lcd ' .. vim.fn.fnameescape(target))
  parser.invalidate_root_cache()
  local ok, err = pcall(fn)
  vim.cmd('lcd ' .. vim.fn.fnameescape(prev))
  parser.invalidate_root_cache()
  if not ok then error(err, 0) end
end

local function git(args, cwd)
  local result = vim.system(vim.list_extend({ 'git' }, args), { text = true, cwd = cwd }):wait()
  if result.code ~= 0 then
    error('git failed: ' .. table.concat(args, ' ') .. '\n' .. (result.stderr or ''), 2)
  end
  return (result.stdout or ''):gsub('%s+$', '')
end

-- Give each tree case its own repository so ancestor repos and directories
-- on the host cannot change path resolution or all_deleted results.
local function with_repo(fn)
  local target = vim.fn.tempname() .. '-parser'
  vim.fn.mkdir(target, 'p')
  git({ 'init', '-q' }, target)
  local ok, err = pcall(with_cwd, target, fn)
  vim.fn.delete(target, 'rf')
  if not ok then error(err, 0) end
end

-- ============================================================================
-- group: files_to_tree_nodes
-- ============================================================================

r.group('files_to_tree_nodes')

r.run('flat files become root-level file nodes', function()
  with_repo(function()
    -- Paths must be relative to this fixture repository.
    local files = {
      { path = 'a.txt', xy = 'M ', x = 'M', y = ' ' },
      { path = 'b.txt', xy = ' M', x = ' ', y = 'M' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'staged')
    r.assert_eq(#nodes, 2)
    r.assert_eq(nodes[1].name, 'a.txt')
    r.assert_eq(nodes[1].type, 'file')
    r.assert_eq(nodes[1].section, 'staged')
    r.assert_eq(nodes[2].name, 'b.txt')
  end)
end)

r.run('nested paths build a directory tree', function()
  with_repo(function()
    local files = {
      { path = 'src/a.lua', xy = 'M ', x = 'M', y = ' ' },
      { path = 'src/sub/b.lua', xy = 'M ', x = 'M', y = ' ' },
      { path = 'top.txt', xy = 'M ', x = 'M', y = ' ' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'staged')
    -- src/ directory + top.txt file
    r.assert_eq(#nodes, 2)
    -- alphabetical sort: directory 'src' first, then file 'top.txt'
    r.assert_eq(nodes[1].name, 'src')
    r.assert_eq(nodes[1].type, 'directory')
    r.assert_eq(nodes[2].name, 'top.txt')
    -- Inside src: a.lua + sub/
    local src = nodes[1]
    r.assert_eq(#src.children, 2)
    -- 'sub' is a directory, comes first; 'a.lua' is a file, comes second
    local sub = src.children[1]
    local a = src.children[2]
    r.assert_eq(sub.name, 'sub')
    r.assert_eq(sub.type, 'directory')
    r.assert_eq(a.name, 'a.lua')
    r.assert_eq(a.type, 'file')
  end)
end)

r.run('expanded_dirs overrides default directory expansion', function()
  with_repo(function()
    local cwd = parser.git_root()
    local files = { { path = 'src/a.lua', xy = 'M ', x = 'M', y = ' ' } }
    local nodes = parser.files_to_tree_nodes(files, { [cwd .. '/src'] = false }, 'staged')
    r.assert_eq(nodes[1].name, 'src')
    r.assert_eq(nodes[1].expanded, false)
  end)
end)

r.run('directory with all deleted files is all_deleted', function()
  with_repo(function()
    local files = {
      { path = 'src/a.lua', xy = 'D ', x = 'D', y = ' ' },
      { path = 'src/sub/b.lua', xy = 'D ', x = 'D', y = ' ' },
      { path = 'src/sub/c.lua', xy = 'D ', x = 'D', y = ' ' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'staged')
    r.assert_eq(#nodes, 1)
    r.assert_eq(nodes[1].name, 'src')
    r.assert_eq(nodes[1].all_deleted, true)
    r.assert_eq(nodes[1].children[1].name, 'sub')
    r.assert_eq(nodes[1].children[1].all_deleted, true)
  end)
end)

r.run('directory still on disk is not all_deleted even if its only change is a deletion', function()
  with_repo(function()
    local cwd = parser.git_root()
    vim.fn.mkdir(cwd .. '/src', 'p')
    vim.fn.writefile({}, cwd .. '/src/kept.lua')
    local files = {
      { path = 'src/a.lua', xy = 'D ', x = 'D', y = ' ' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'staged')
    r.assert_eq(#nodes, 1)
    r.assert_eq(nodes[1].name, 'src')
    r.assert_eq(nodes[1].all_deleted, false)
  end)
end)

r.run('directory with any non-deleted file is not all_deleted', function()
  with_repo(function()
    local files = {
      { path = 'src/a.lua', xy = 'D ', x = 'D', y = ' ' },
      { path = 'src/b.lua', xy = 'M ', x = 'M', y = ' ' },
      { path = 'src/sub/c.lua', xy = 'D ', x = 'D', y = ' ' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'staged')
    r.assert_eq(#nodes, 1)
    r.assert_eq(nodes[1].all_deleted, false)
    r.assert_eq(nodes[1].children[1].name, 'sub')
    r.assert_eq(nodes[1].children[1].all_deleted, true)
  end)
end)

r.run('all_deleted respects unstaged delete column', function()
  with_repo(function()
    local files = {
      { path = 'src/a.lua', xy = ' D', x = ' ', y = 'D' },
      { path = 'src/b.lua', xy = ' D', x = ' ', y = 'D' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'unstaged')
    r.assert_eq(#nodes, 1)
    r.assert_eq(nodes[1].all_deleted, true)
  end)
end)

r.run('all_deleted in changes section counts either delete column', function()
  with_repo(function()
    local files = {
      { path = 'src/a.lua', xy = 'D ', x = 'D', y = ' ' },
      { path = 'src/b.lua', xy = ' D', x = ' ', y = 'D' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'changes')
    r.assert_eq(#nodes, 1)
    r.assert_eq(nodes[1].all_deleted, true)
  end)
end)

r.run('untracked files never make a directory all_deleted', function()
  with_repo(function()
    local files = {
      { path = 'src/a.lua', xy = '??', x = '?', y = '?' },
      { path = 'src/b.lua', xy = '??', x = '?', y = '?' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'untracked')
    r.assert_eq(#nodes, 1)
    r.assert_eq(nodes[1].all_deleted, false)
  end)
end)

-- ============================================================================
-- group: git_root cache auto-invalidation
-- ============================================================================

r.group('git_root cache')

r.run('cache hit when cached root remains valid', function()
  with_repo(function()
    local first = parser.git_root()
    r.assert_eq(first, vim.fn.getcwd())
    r.assert_eq(parser.git_root(), first)
  end)
end)

r.run('cache invalidates when .git disappears and resolves the enclosing repository', function()
  with_repo(function()
    local outer = vim.fn.getcwd()
    local inner = outer .. '/inner'
    vim.fn.mkdir(inner, 'p')
    git({ 'init', '-q' }, inner)
    with_cwd(inner, function()
      r.assert_eq(parser.git_root(), inner)
      vim.fn.delete(inner .. '/.git', 'rf')
      r.assert_eq(parser.git_root(), outer)
    end)
  end)
end)

r.run('cache detects a nested repository appearing above the same cwd', function()
  with_repo(function()
    local outer = vim.fn.getcwd()
    local inner = outer .. '/nested'
    local cwd = inner .. '/deeper'
    vim.fn.mkdir(cwd, 'p')
    with_cwd(cwd, function()
      r.assert_eq(parser.git_root(), outer)
      git({ 'init', '-q' }, inner)
      r.assert_eq(parser.git_root(), inner)
      vim.fn.delete(inner .. '/.git', 'rf')
      r.assert_eq(parser.git_root(), outer)
    end)
  end)
end)

r.run('cache detects a worktree .git file appearing at the same cwd', function()
  with_repo(function()
    local outer = vim.fn.getcwd()
    git({ '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '--allow-empty', '-qm', 'fixture' }, outer)
    local worktree = outer .. '/worktree'
    vim.fn.mkdir(worktree, 'p')
    with_cwd(worktree, function()
      r.assert_eq(parser.git_root(), outer)
      git({ 'worktree', 'add', '--detach', worktree }, outer)
      r.assert_eq(vim.uv.fs_stat(worktree .. '/.git').type, 'file')
      r.assert_eq(parser.git_root(), worktree)
    end)
  end)
end)

r.finish()
