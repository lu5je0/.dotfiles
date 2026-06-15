local state = require('lu5je0.ext.tree-sidebar.state')
local git_ops = require('lu5je0.ext.git.common.git-ops')

local M = {}

local log_batch = git_ops.log_batch

local function git_root()
  return require('lu5je0.ext.tree-sidebar.sources.git_changes.parser').git_root()
end

local function run_git(args, error_prefix)
  return git_ops.run_git(args, error_prefix, git_root())
end

local function hash_file(abs_path, write)
  return git_ops.hash_file(abs_path, write, git_root())
end

local function get_undo_stack()
  state.git_changes._undo_stack = state.git_changes._undo_stack or {}
  return state.git_changes._undo_stack
end

local function push_undo(label, ops)
  git_ops.push_undo(get_undo_stack(), label, ops)
end

local function git_changes_mod()
  return require('lu5je0.ext.tree-sidebar.sources.git_changes')
end

local function refresh()
  git_changes_mod().refresh()
end

local function reload_buf(abs_path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == abs_path then
      vim.api.nvim_buf_call(buf, function() vim.cmd('checktime') end)
      break
    end
  end
end

-- ── helpers ─────────────────────────────────────────────

local function find_section_for_line(line)
  return git_changes_mod().find_section_for_line(line)
end

local function effective_section_for_file(section_key, node)
  if section_key ~= 'changes' then
    return section_key
  end
  local x = (node.x or (node.xy or ''):sub(1, 1))
  local y = (node.y or (node.xy or ''):sub(2, 2))
  if x == '?' then
    return 'untracked'
  elseif y ~= ' ' then
    return 'unstaged'
  else
    return 'staged'
  end
end

local function get_file_item()
  if not state:is_open() then return nil, nil end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.git_changes.display_items[line]
  if not item or item._is_section or not item.node or item.type ~= 'file' then
    return nil, nil
  end
  return item, find_section_for_line(line)
end

local function collect_files_under(node)
  local files = {}
  local function walk(n)
    if not n then return end
    if n.type == 'file' then
      files[#files + 1] = n
    elseif n.children then
      for _, child in ipairs(n.children) do walk(child) end
    end
  end
  walk(node)
  return files
end

local function get_section_key()
  if not state:is_open() then return nil end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.git_changes.display_items[line]
  if item and item._is_section then
    return item.section
  end
  return find_section_for_line(line)
end

-- ── stage file (a) ──────────────────────────────────────

function M.stage_file()
  local item, section_key = get_file_item()
  if not item then return end
  local node = item.node
  local eff = effective_section_for_file(section_key, node)

  if eff == 'staged' then
    vim.notify('Already staged', vim.log.levels.INFO)
    return
  end

  local path = node.rel_path or node.name
  local cwd = vim.fn.getcwd()
  local abs_path = cwd .. '/' .. path
  if not run_git({ 'git', 'add', '--', path }, 'Failed to stage: ') then return end

  local snapshot = git_ops.index_snapshot({ path })
  push_undo('staged', { { type = 'reset_paths', paths = { path }, expected_index = snapshot } })
  log_batch('staged', eff, 1, function(write)
    write(string.format('Staged %s. Restore: git reset HEAD -- %s', abs_path, abs_path))
  end)
  vim.notify('Staged ' .. path, vim.log.levels.INFO)
  refresh()
end

-- ── stage section (A) ───────────────────────────────────

function M.stage_section()
  local section_key = get_section_key()
  if not section_key then return end

  local sections = state.git_changes.sections
  local files = sections[section_key] or {}
  local stage_paths = {}
  for _, file in ipairs(files) do
    local x, y = (file.xy or ''):sub(1, 1), (file.xy or ''):sub(2, 2)
    if x == '?' or (y ~= ' ' and y ~= '?') then
      stage_paths[#stage_paths + 1] = file.path
    end
  end

  if #stage_paths == 0 then
    vim.notify('Already staged', vim.log.levels.INFO)
    return
  end

  local args = { 'git', 'add', '--' }
  for _, p in ipairs(stage_paths) do args[#args + 1] = p end
  if not run_git(args, 'Failed to stage section: ') then return end

  local snapshot = git_ops.index_snapshot(stage_paths)
  push_undo('staged', { { type = 'reset_paths', paths = stage_paths, expected_index = snapshot } })
  local cwd = vim.fn.getcwd()
  log_batch('staged', section_key, #stage_paths, function(write)
    for _, p in ipairs(stage_paths) do
      write(string.format('Staged %s/%s', cwd, p))
    end
  end)
  vim.notify(string.format('Staged %d files', #stage_paths), vim.log.levels.INFO)
  refresh()
end

-- ── unstage file (u) ────────────────────────────────────

function M.unstage_file()
  local item, section_key = get_file_item()
  if not item then return end
  local node = item.node
  local eff = effective_section_for_file(section_key, node)

  if eff ~= 'staged' then
    vim.notify('Not staged', vim.log.levels.INFO)
    return
  end

  local path = node.rel_path or node.name
  local cwd = vim.fn.getcwd()
  local abs_path = cwd .. '/' .. path
  if not run_git({ 'git', 'reset', 'HEAD', '--', path }, 'Failed to unstage: ') then return end

  local snapshot = git_ops.index_snapshot({ path })
  push_undo('unstaged', { { type = 'add_paths', paths = { path }, expected_index = snapshot } })
  log_batch('unstaged', 'staged', 1, function(write)
    write(string.format('Unstaged %s. Restore: git add %s', abs_path, abs_path))
  end)
  vim.notify('Unstaged ' .. path, vim.log.levels.INFO)
  refresh()
end

-- ── discard file (x) ────────────────────────────────────

--- Discard a single file. Returns undo op on success, nil on failure.
local function discard_single_file(node, section_key)
  local eff = effective_section_for_file(section_key, node)
  local path = node.rel_path or node.name
  local root = git_root()
  local abs_path = root .. '/' .. path

  if eff == 'untracked' then
    local blob = hash_file(abs_path, true)
    if not blob then return nil end
    os.remove(abs_path)
    return { type = 'restore_blobs', files = { { path = path, blob = blob, expected_absent = true } } }
  elseif eff == 'unstaged' then
    local existed = vim.uv.fs_stat(abs_path) ~= nil
    local blob = existed and hash_file(abs_path, true) or nil
    if not run_git({ 'git', 'checkout', '--', path }, 'Failed to restore: ') then return nil end
    local expected_blob = hash_file(abs_path, false)
    if not expected_blob then return nil end
    if blob then
      return { type = 'restore_blobs', files = { { path = path, blob = blob, expected_blob = expected_blob } } }
    else
      return { type = 'restore_blobs', files = { { path = path, delete = true, expected_blob = expected_blob } } }
    end
  elseif eff == 'staged' then
    if not run_git({ 'git', 'reset', 'HEAD', '--', path }, 'Failed to unstage: ') then return nil end
    local snapshot = git_ops.index_snapshot({ path })
    return { type = 'add_paths', paths = { path }, expected_index = snapshot }
  end
end

function M.discard_file()
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.git_changes.display_items[line]
  if not item or item._is_section or not item.node then return end
  local section_key = find_section_for_line(line)
  local root = git_root()

  if item.type == 'dir' then
    local files = collect_files_under(item.node)
    if #files == 0 then return end
    local choice = vim.fn.confirm('Discard ' .. #files .. ' files in ' .. item.node.name .. '/?', '&Yes\n&No', 2)
    if choice ~= 1 then return end
    local ops = {}
    for _, node in ipairs(files) do
      local op = discard_single_file(node, section_key)
      if op then ops[#ops + 1] = op end
    end
    if #ops > 0 then
      push_undo('discarded dir', ops)
    end
    for _, node in ipairs(files) do
      reload_buf(root .. '/' .. (node.rel_path or node.name))
    end
    vim.notify(string.format('Discarded %d files', #ops), vim.log.levels.INFO)
    refresh()
    return
  end

  if item.type ~= 'file' then return end
  local op = discard_single_file(item.node, section_key)
  if op then
    push_undo('discarded', { op })
    local path = item.node.rel_path or item.node.name
    reload_buf(root .. '/' .. path)
    vim.notify('Discarded ' .. path, vim.log.levels.INFO)
  end
  refresh()
end

-- ── discard section (X) ─────────────────────────────────

function M.discard_section()
  local section_key = get_section_key()
  if not section_key then return end

  local sections = state.git_changes.sections
  local files = sections[section_key] or {}
  if #files == 0 then return end

  local label = section_key:sub(1, 1):upper() .. section_key:sub(2)
  local choice = vim.fn.confirm('Discard all ' .. label .. ' (' .. #files .. ' files)?', '&Yes\n&No', 2)
  if choice ~= 1 then return end

  local cwd = vim.fn.getcwd()

  if section_key == 'untracked' then
    local abs_paths = {}
    for _, file in ipairs(files) do
      abs_paths[#abs_paths + 1] = cwd .. '/' .. file.path
    end
    local stdin = table.concat(abs_paths, '\n')
    local result = vim.system({ 'git', 'hash-object', '-w', '--stdin-paths' }, { text = true, cwd = cwd, stdin = stdin }):wait()
    if result.code ~= 0 then
      vim.notify('Failed to hash files: ' .. (result.stderr or ''), vim.log.levels.ERROR)
      return
    end
    local blobs = {}
    for line in (result.stdout or ''):gmatch('[^\n]+') do blobs[#blobs + 1] = line end
    if #blobs ~= #files then
      vim.notify('Hash mismatch', vim.log.levels.ERROR)
      return
    end
    local restore_files = {}
    log_batch('removed_untracked', 'untracked', #files, function(write)
      for i, file in ipairs(files) do
        restore_files[#restore_files + 1] = { path = file.path, blob = blobs[i], expected_absent = true }
        os.remove(abs_paths[i])
        write(string.format('Deleted %s. Restore: git show %s > %s', abs_paths[i], blobs[i], abs_paths[i]))
      end
    end)
    push_undo('removed untracked', { { type = 'restore_blobs', files = restore_files } })
    vim.notify(string.format('Removed %d untracked files', #files), vim.log.levels.INFO)
  elseif section_key == 'unstaged' or section_key == 'changes' then
    local target_files = {}
    local staged_only_paths = {}
    for _, file in ipairs(files) do
      local x = (file.xy or ''):sub(1, 1)
      local y = (file.xy or ''):sub(2, 2)
      if x == '?' or (y ~= ' ' and y ~= '?') then
        target_files[#target_files + 1] = file
      elseif section_key == 'changes' and x ~= ' ' and x ~= '?' and y == ' ' then
        staged_only_paths[#staged_only_paths + 1] = file.path
      end
    end
    if #target_files == 0 and #staged_only_paths == 0 then return end

    local staged_undo_op = nil
    if #staged_only_paths > 0 then
      local args = { 'git', 'reset', 'HEAD', '--' }
      for _, p in ipairs(staged_only_paths) do args[#args + 1] = p end
      if not run_git(args, 'Failed to unstage: ') then return end
      local snapshot = git_ops.index_snapshot(staged_only_paths)
      staged_undo_op = { type = 'add_paths', paths = staged_only_paths, expected_index = snapshot }
    end

    if #target_files == 0 then
      push_undo('unstaged', { staged_undo_op })
      vim.notify(string.format('Unstaged %d files', #staged_only_paths), vim.log.levels.INFO)
      refresh()
      return
    end

    local existing_files = {}
    local existing_indices = {}
    for i, file in ipairs(target_files) do
      local abs_path = cwd .. '/' .. file.path
      if vim.uv.fs_stat(abs_path) then
        existing_files[#existing_files + 1] = abs_path
        existing_indices[#existing_indices + 1] = i
      end
    end
    local pre_blobs = {}
    if #existing_files > 0 then
      local stdin = table.concat(existing_files, '\n')
      local result = vim.system({ 'git', 'hash-object', '-w', '--stdin-paths' }, { text = true, cwd = cwd, stdin = stdin }):wait()
      if result.code ~= 0 then
        vim.notify('Failed to hash files: ' .. (result.stderr or ''), vim.log.levels.ERROR)
        return
      end
      local idx = 1
      for line in (result.stdout or ''):gmatch('[^\n]+') do
        pre_blobs[existing_indices[idx]] = line
        idx = idx + 1
      end
    end

    local checkout_files = {}
    local untracked_files = {}
    for _, file in ipairs(target_files) do
      if (file.xy or '') == '??' then
        untracked_files[#untracked_files + 1] = file
      else
        checkout_files[#checkout_files + 1] = file
      end
    end

    if #checkout_files > 0 then
      local args = { 'git', 'checkout', '--' }
      for _, f in ipairs(checkout_files) do args[#args + 1] = f.path end
      if not run_git(args, 'Failed to restore files: ') then return end
    end
    for _, file in ipairs(untracked_files) do
      os.remove(cwd .. '/' .. file.path)
    end

    local expected_blobs = {}
    local checkout_post = {}
    for i, file in ipairs(target_files) do
      if (file.xy or '') ~= '??' then
        checkout_post[#checkout_post + 1] = { idx = i, abs_path = cwd .. '/' .. file.path }
      end
    end
    if #checkout_post > 0 then
      local paths_str = ''
      for _, cp in ipairs(checkout_post) do paths_str = paths_str .. cp.abs_path .. '\n' end
      local post_result = vim.system({ 'git', 'hash-object', '--stdin-paths' }, { text = true, cwd = cwd, stdin = paths_str }):wait()
      if post_result.code == 0 then
        local idx = 1
        for line in (post_result.stdout or ''):gmatch('[^\n]+') do
          expected_blobs[checkout_post[idx].idx] = line
          idx = idx + 1
        end
      end
    end

    local restore_files = {}
    log_batch('reverted', section_key, #target_files, function(write)
      for i, file in ipairs(target_files) do
        local abs_path = cwd .. '/' .. file.path
        local blob = pre_blobs[i]
        local eb = expected_blobs[i]
        if (file.xy or '') == '??' then
          if blob then
            restore_files[#restore_files + 1] = { path = file.path, blob = blob, expected_absent = true }
            write(string.format('Deleted %s. Restore: git show %s > %s', abs_path, blob, abs_path))
          end
        elseif blob then
          restore_files[#restore_files + 1] = { path = file.path, blob = blob, expected_blob = eb }
          write(string.format('Restored %s. Undo: git show %s > %s', abs_path, blob, abs_path))
        else
          restore_files[#restore_files + 1] = { path = file.path, delete = true, expected_blob = eb }
          write(string.format('Restored %s. Undo: delete %s', abs_path, abs_path))
        end
      end
    end)
    local ops = {}
    if staged_undo_op then
      ops[#ops + 1] = staged_undo_op
    end
    ops[#ops + 1] = { type = 'restore_blobs', files = restore_files }
    push_undo('reverted', ops)
    for _, file in ipairs(target_files) do
      reload_buf(cwd .. '/' .. file.path)
    end
    vim.notify(string.format('Reverted %d files', #target_files + #staged_only_paths), vim.log.levels.INFO)
  elseif section_key == 'staged' then
    local args = { 'git', 'reset', 'HEAD', '--' }
    local paths = {}
    for _, file in ipairs(files) do
      args[#args + 1] = file.path
      paths[#paths + 1] = file.path
    end
    if not run_git(args, 'Failed to unstage section: ') then return end
    local snapshot = git_ops.index_snapshot(paths)
    push_undo('unstaged', { { type = 'add_paths', paths = paths, expected_index = snapshot } })
    log_batch('unstaged', 'staged', #files, function(write)
      for _, file in ipairs(files) do
        write(string.format('Unstaged %s/%s', cwd, file.path))
      end
    end)
    vim.notify(string.format('Unstaged %d files', #files), vim.log.levels.INFO)
  end
  refresh()
end

-- ── drop stash (x on stash entry) ──────────────────────

function M.drop_stash()
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.git_changes.display_items[line]
  if not item or not item.node or not item.node._is_stash then return end

  local stash_ref = item.node.stash_ref
  local sha_result = vim.system({ 'git', 'rev-parse', stash_ref }, { text = true }):wait()
  local sha = (sha_result.stdout or ''):gsub('%s+$', '')
  if sha_result.code ~= 0 or sha == '' then
    vim.notify('Failed to resolve ' .. stash_ref, vim.log.levels.ERROR)
    return
  end

  local drop_result = vim.system({ 'git', 'stash', 'drop', stash_ref }, { text = true }):wait()
  if drop_result.code ~= 0 then
    vim.notify('Failed to drop ' .. stash_ref .. ': ' .. (drop_result.stderr or ''), vim.log.levels.ERROR)
    return
  end

  local stash_msg = item.node.stash_message or ''
  push_undo('dropped', { { type = 'store_stash', sha = sha, message = stash_msg } })
  log_batch('dropped', 'stash', 1, function(write)
    write(string.format('Dropped %s. Restore: git stash store -m %s %s',
      stash_ref, vim.fn.shellescape(stash_msg), sha))
  end)
  vim.notify('Dropped ' .. stash_ref, vim.log.levels.INFO)

  local entries = state.git_changes._stash_entries or {}
  for i, s in ipairs(entries) do
    if s.ref == stash_ref then table.remove(entries, i); break end
  end
  git_changes_mod().render()
  pcall(vim.api.nvim_win_set_cursor, state.win, { math.min(line, vim.api.nvim_buf_line_count(state.buf)), 0 })
  git_changes_mod().reload_stash_list()
end

-- ── undo (U) ────────────────────────────────────────────

function M.undo_last_action()
  local stack = get_undo_stack()
  local entry = stack[#stack]
  git_ops.undo_last_action(stack, vim.fn.getcwd(), function()
    if entry then
      local cwd = vim.fn.getcwd()
      for _, op in ipairs(entry.ops) do
        if op.type == 'restore_blobs' then
          for _, file in ipairs(op.files or {}) do
            reload_buf(cwd .. '/' .. file.path)
          end
        end
      end
    end
    refresh()
    git_changes_mod().reload_stash_list(function()
      for i, item in ipairs(state.git_changes.display_items or {}) do
        if item.node and item.node._is_stash and item.node.stash_ref == 'stash@{0}' then
          pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
          return
        end
      end
    end)
  end)
end

return M
