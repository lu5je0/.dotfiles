local core = require('lu5je0.ext.git.project-log.core')
local diff = require('lu5je0.ext.git.git-status.diff')
local help = require('lu5je0.ext.git.common.help')
local scheduler = require('lu5je0.ext.git.common.scheduler')
local status_ui = require('lu5je0.ext.git.git-status.ui')
local tree = require('lu5je0.ext.git.common.tree')
local common_ui = require('lu5je0.ext.git.common.ui')
local env_keeper = require('lu5je0.misc.env-keeper')
local config = require('lu5je0.ext.git.config')

local M = {}

local load_status

local state = {
  session = 0,
  job = nil,
  diff_job = nil,
  diff_job2 = nil,
  log_buf = nil,
  log_win = nil,
  diff_buf = nil,
  diff_buf2 = nil,
  diff_win = nil,
  diff_win2 = nil,
  repo_root = nil,
  head = nil,
  merge = nil,
  commits = {},
  display_items = {},
  header_count = 0,
  preview_key = nil,
  stashes = {},
  stash_expanded = true,
  undo_stack = {},
  diff_mode = env_keeper.get('git_status_diff_mode', 'single'),
  diff_changes_only = env_keeper.get('git_status_diff_changes_only', false),
  closing_diff_windows = false,
  tree_opts = {},
  render = function(s) status_ui.render(s) end,
  refresh_commit_line = function(s, line) status_ui.refresh_commit_line(s, line) end,
}

-- ── helpers ──────────────────────────────────────────────

local function kill_job(name)
  if state[name] then
    pcall(function() state[name]:kill() end)
    state[name] = nil
  end
end

local function kill_jobs()
  kill_job('job')
  diff.kill_jobs(state)
end

local function is_active_session(session)
  return state.session == session
end

local function cleanup()
  kill_jobs()
  diff.close_windows(state)
  state.session = state.session + 1
  state.log_buf = nil
  state.log_win = nil
  state.commits = {}
  state.display_items = {}
  state.header_count = 0
  state.preview_key = nil
  state.stashes = {}
  state.stash_expanded = true
  state.undo_stack = {}
  state.head = nil
  state.merge = nil
end

local function close_all()
  if state.log_win and vim.api.nvim_win_is_valid(state.log_win) then
    pcall(vim.api.nvim_win_close, state.log_win, true)
  end
  cleanup()
end

-- ── item helpers ─────────────────────────────────────────

local function item_under_cursor()
  local item = tree.item_under_cursor(state)
  if not item or item.type == 'header' or item.type == 'blank' or item.type == 'stash_header' then
    return nil
  end
  return item
end

local function get_section_and_file(item)
  if not item then
    return nil, nil
  end
  local section = state.commits[item.commit_idx]
  local file = section and section.files[item.file_idx] or nil
  return section, file
end

local function get_non_stash_section(item)
  if not item or item.stash then
    return nil
  end
  local section = state.commits[item.commit_idx]
  if not section or section.section == 'stash' then
    return nil
  end
  return section
end

-- ── diff preview ─────────────────────────────────────────

local function show_file_diff(auto_preview)
  if auto_preview and not diff.has_window(state) then
    return false
  end
  local item = item_under_cursor()
  if not item or item.type ~= 'file' then
    return false
  end
  local section, file = get_section_and_file(item)
  if not section or not file then
    return false
  end
  local preview_key = diff.make_preview_key(state, section, file)
  if state.preview_key == preview_key then
    return true
  end
  state.preview_key = preview_key
  if state.diff_mode == 'dual' then
    diff.show_dual(state, section, file)
  else
    diff.show_single(state, section, file)
  end
  return true
end

-- ── actions ──────────────────────────────────────────────

local function discard_log(msg)
  local log_line = string.format('%s %s', os.date('%Y-%m-%d %H:%M:%S'), msg)
  vim.fn.writefile({ log_line }, vim.fn.stdpath('log') .. '/git-status.log', 'a')
  vim.api.nvim_echo({ { msg } }, true, { kind = 'emsg' })
end

local function git_path_args(...)
  local args = { ... }
  args[#args + 1] = '--'
  return args
end

local function append_path_list(args, paths)
  for _, path in ipairs(paths or {}) do
    if path and path ~= '' then
      args[#args + 1] = path
    end
  end
  return args
end

local function append_paths(args, files)
  for _, file in ipairs(files or {}) do
    if file.path and file.path ~= '' then
      args[#args + 1] = file.path
    end
  end
  return args
end

local function path_count(args)
  local count = 0
  local after_separator = false
  for _, arg in ipairs(args) do
    if after_separator then
      count = count + 1
    elseif arg == '--' then
      after_separator = true
    end
  end
  return count
end

local function file_paths(files)
  local paths = {}
  for _, file in ipairs(files or {}) do
    if file.path and file.path ~= '' then
      paths[#paths + 1] = file.path
    end
  end
  return paths
end

local function run_git(args, error_prefix)
  local result = vim.system(args, { text = true, cwd = state.repo_root }):wait()
  if result.code ~= 0 then
    local stderr = (result.stderr or ''):gsub('%s+$', '')
    vim.notify(string.format('%s%s', error_prefix or 'Git command failed: ', stderr), vim.log.levels.ERROR)
    return false, result
  end
  return true, result
end

local function hash_file(abs_path, write)
  local args = { 'git', 'hash-object' }
  if write then
    args[#args + 1] = '-w'
  end
  args[#args + 1] = abs_path
  local ok, result = run_git(args, 'Failed to hash file: ')
  if not ok then
    return nil
  end
  local blob = (result.stdout or ''):gsub('%s+$', '')
  return blob ~= '' and blob or nil
end

local function write_blob(blob, abs_path)
  vim.fn.mkdir(vim.fn.fnamemodify(abs_path, ':h'), 'p')
  local result = vim.system({ 'git', 'cat-file', 'blob', blob }, { cwd = state.repo_root }):wait()
  if result.code ~= 0 then
    vim.notify('Failed to read blob ' .. blob, vim.log.levels.ERROR)
    return false
  end
  local fd = vim.uv.fs_open(abs_path, 'w', 420)
  if not fd then
    vim.notify('Failed to open ' .. abs_path, vim.log.levels.ERROR)
    return false
  end
  vim.uv.fs_write(fd, result.stdout or '', 0)
  vim.uv.fs_close(fd)
  return true
end

local function reload_status()
  state.preview_key = nil
  load_status()
end

local function push_undo(label, ops)
  if ops and #ops > 0 then
    state.undo_stack[#state.undo_stack + 1] = { label = label, ops = ops }
  end
end

local function undo_restore_blobs(op)
  for _, file in ipairs(op.files or {}) do
    local abs_path = state.repo_root .. '/' .. file.path
    if file.expected_absent then
      if vim.uv.fs_stat(abs_path) then
        vim.notify('Undo skipped: ' .. abs_path .. ' already exists', vim.log.levels.WARN)
        return false
      end
    elseif file.expected_blob then
      if not vim.uv.fs_stat(abs_path) then
        vim.notify('Undo skipped: ' .. abs_path .. ' no longer exists', vim.log.levels.WARN)
        return false
      end
      local current_blob = hash_file(abs_path, false)
      if current_blob ~= file.expected_blob then
        vim.notify('Undo skipped: ' .. abs_path .. ' changed after discard', vim.log.levels.WARN)
        return false
      end
    else
      vim.notify('Undo skipped: cannot verify ' .. abs_path, vim.log.levels.WARN)
      return false
    end
  end

  for _, file in ipairs(op.files or {}) do
    local abs_path = state.repo_root .. '/' .. file.path
    if file.delete then
      os.remove(abs_path)
    elseif not write_blob(file.blob, abs_path) then
      return false
    end
  end
  return true
end

local function run_undo_op(op)
  if op.type == 'reset_paths' then
    local ok = run_git(append_path_list(git_path_args('git', 'reset', 'HEAD'), op.paths), 'Undo failed: ')
    return ok
  elseif op.type == 'add_paths' then
    local ok = run_git(append_path_list(git_path_args('git', 'add'), op.paths), 'Undo failed: ')
    return ok
  elseif op.type == 'restore_blobs' then
    return undo_restore_blobs(op)
  elseif op.type == 'store_stash' then
    local ok = run_git({ 'git', 'stash', 'store', '-m', op.message, op.sha }, 'Undo failed: ')
    return ok
  end
  return false
end

local function undo_last_action()
  local entry = state.undo_stack[#state.undo_stack]
  if not entry then
    vim.notify('Nothing to undo', vim.log.levels.INFO)
    return
  end

  for i = #entry.ops, 1, -1 do
    if not run_undo_op(entry.ops[i]) then
      return
    end
  end
  table.remove(state.undo_stack)
  vim.notify('Undid ' .. entry.label, vim.log.levels.INFO)
  reload_status()
end

local function stage_section()
  local section = get_non_stash_section(item_under_cursor())
  if not section then
    return
  end
  if section.section ~= 'untracked' and section.section ~= 'unstaged' then
    vim.notify('Already staged', vim.log.levels.INFO)
    return
  end

  local args = append_paths(git_path_args('git', 'add'), section.files)
  local count = path_count(args)
  if count == 0 then
    return
  end
  if not run_git(args, 'Failed to stage section: ') then
    return
  end
  push_undo('stage section', { { type = 'reset_paths', paths = file_paths(section.files) } })
  vim.notify(string.format('Staged %d files', count), vim.log.levels.INFO)
  reload_status()
end

local function discard_section()
  local section = get_non_stash_section(item_under_cursor())
  if not section then
    return false
  end

  local files = section.files or {}
  if #files == 0 then
    return true
  end

  if section.section == 'untracked' then
    local restore_files = {}
    for _, file in ipairs(files) do
      local abs_path = state.repo_root .. '/' .. file.path
      local blob = hash_file(abs_path, true)
      if not blob then
        return true
      end
      restore_files[#restore_files + 1] = { path = file.path, blob = blob, expected_absent = true }
      os.remove(abs_path)
      discard_log(string.format('Deleted %s. Restore: git show %s > %s', abs_path, blob, abs_path))
    end
    push_undo('discard section', { { type = 'restore_blobs', files = restore_files } })
  elseif section.section == 'unstaged' then
    local restore_files = {}
    for _, file in ipairs(files) do
      local abs_path = state.repo_root .. '/' .. file.path
      local blob = vim.uv.fs_stat(abs_path) and hash_file(abs_path, true) or nil
      if not run_git({ 'git', 'checkout', '--', file.path }, 'Failed to restore file: ') then
        return true
      end
      local expected_blob = hash_file(abs_path, false)
      if not expected_blob then
        return true
      end
      if blob then
        restore_files[#restore_files + 1] = { path = file.path, blob = blob, expected_blob = expected_blob }
        discard_log(string.format('Restored %s from index. Undo: git show %s > %s', abs_path, blob, abs_path))
      else
        restore_files[#restore_files + 1] = { path = file.path, delete = true, expected_blob = expected_blob }
        discard_log(string.format('Restored %s from index. Undo: delete %s', abs_path, abs_path))
      end
    end
    push_undo('discard section', { { type = 'restore_blobs', files = restore_files } })
  elseif section.section == 'staged' then
    local args = append_paths(git_path_args('git', 'reset', 'HEAD'), files)
    if not run_git(args, 'Failed to unstage section: ') then
      return true
    end
    push_undo('discard section', { { type = 'add_paths', paths = file_paths(files) } })
    for _, file in ipairs(files) do
      local abs_path = state.repo_root .. '/' .. file.path
      discard_log(string.format('Unstaged %s. Restore: git add %s', abs_path, abs_path))
    end
  else
    return false
  end

  reload_status()
  return true
end

local function discard_change()
  local item = item_under_cursor()
  if not item then
    return
  end

  -- stash commit line: drop the stash entry
  if item.type == 'commit' and item.stash then
    local commit = state.commits[item.commit_idx]
    if not commit or not commit.stash_ref then
      return
    end
    local sha_result = vim.system({ 'git', 'rev-parse', commit.stash_ref }, { text = true, cwd = state.repo_root }):wait()
    local sha = (sha_result.stdout or ''):gsub('%s+$', '')
    if sha_result.code ~= 0 or sha == '' then
      vim.notify('Failed to resolve ' .. commit.stash_ref, vim.log.levels.ERROR)
      return
    end
    local drop_result = vim.system({ 'git', 'stash', 'drop', commit.stash_ref }, { text = true, cwd = state.repo_root }):wait()
    if drop_result.code ~= 0 then
      vim.notify('Failed to drop ' .. commit.stash_ref .. ': ' .. (drop_result.stderr or ''), vim.log.levels.ERROR)
      return
    end
    local stash_msg = commit.stash_label:sub(#commit.stash_ref + 3)
    local restore_cmd = string.format('cd %s && git stash store -m %s %s', vim.fn.shellescape(state.repo_root), vim.fn.shellescape(stash_msg), sha)
    local notify_msg = string.format('Dropped %s. Restore: %s', commit.stash_ref, restore_cmd)
    discard_log(notify_msg)
    push_undo('drop stash', { { type = 'store_stash', sha = sha, message = stash_msg } })
    reload_status()
    return
  end

  if item.type ~= 'file' then
    return
  end
  local section, file = get_section_and_file(item)
  if not section or not file then
    return
  end

  local abs_path = state.repo_root .. '/' .. file.path

  if section.section == 'untracked' then
    local blob = hash_file(abs_path, true)
    if not blob then
      return
    end
    os.remove(abs_path)
    discard_log(string.format('Deleted %s. Restore: git show %s > %s', abs_path, blob, abs_path))
    push_undo('discard file', {
      { type = 'restore_blobs', files = { { path = file.path, blob = blob, expected_absent = true } } },
    })
  elseif section.section == 'unstaged' then
    local blob = vim.uv.fs_stat(abs_path) and hash_file(abs_path, true) or nil
    if not run_git({ 'git', 'checkout', '--', file.path }, 'Failed to restore file: ') then
      return
    end
    local expected_blob = hash_file(abs_path, false)
    if not expected_blob then
      return
    end
    if blob then
      discard_log(string.format('Restored %s from index. Undo: git show %s > %s', abs_path, blob, abs_path))
      push_undo('discard file', {
        { type = 'restore_blobs', files = { { path = file.path, blob = blob, expected_blob = expected_blob } } },
      })
    else
      discard_log(string.format('Restored %s from index. Undo: delete %s', abs_path, abs_path))
      push_undo('discard file', {
        { type = 'restore_blobs', files = { { path = file.path, delete = true, expected_blob = expected_blob } } },
      })
    end
  elseif section.section == 'staged' then
    if not run_git({ 'git', 'reset', 'HEAD', '--', file.path }, 'Failed to unstage file: ') then
      return
    end
    discard_log(string.format('Unstaged %s. Restore: git add %s', abs_path, abs_path))
    push_undo('discard file', { { type = 'add_paths', paths = { file.path } } })
  end

  reload_status()
end

-- ── load stash files (lazy, per-commit) ──────────────────

local function load_stash_files_for(commit_idx, callback)
  local session = state.session
  local commit = state.commits[commit_idx]
  if not commit or not commit.stash_ref then
    return
  end
  vim.system(
    { 'git', 'stash', 'show', '--name-status', '--find-renames', commit.stash_ref },
    { text = true, cwd = state.repo_root },
    function(result)
      vim.schedule(function()
        if not is_active_session(session) then
          return
        end
        commit.files = core.parse_name_status(result.stdout)
        commit.files_loaded = true
        if callback then
          callback()
        end
      end)
    end
  )
end

local function activate_item()
  local item = tree.item_under_cursor(state)
  if item and item.type == 'stash_header' then
    if state.stash_expanded == false then
      state.stash_expanded = true
      status_ui.render(state)
    else
      local line = vim.api.nvim_win_get_cursor(state.log_win)[1]
      local next_item = state.display_items[line + 1]
      if next_item and next_item.stash then
        vim.api.nvim_win_set_cursor(state.log_win, { line + 1, 0 })
      end
    end
    return
  end
  if item and item.type == 'commit' and item.stash then
    local commit = state.commits[item.commit_idx]
    if commit and not commit.files_loaded then
      load_stash_files_for(item.commit_idx, function()
        tree.open_node(state)
      end)
      return
    end
  end
  if tree.open_node(state) then
    return
  end
  state.preview_key = nil
  show_file_diff()
end

-- ── load status ──────────────────────────────────────────

load_status = function()
  local session = state.session
  status_ui.update_statusline(state, true)

  local head_job = vim.system({ 'git', 'rev-parse', '--abbrev-ref', 'HEAD' }, { text = true, cwd = state.repo_root })
  local merge_job = vim.system({ 'git', 'rev-parse', '--abbrev-ref', '@{upstream}' }, { text = true, cwd = state.repo_root })
  local stash_job = vim.system({ 'git', 'stash', 'list', '--format=%gd%x00%gs' }, { text = true, cwd = state.repo_root })

  state.job = vim.system({
    'git', 'status', '--porcelain=v1', '-z', '--untracked-files=all',
  }, { text = true, cwd = state.repo_root }, function(result)
    vim.schedule(function()
      local head_result = head_job:wait()
      local merge_result = merge_job:wait()
      local stash_result = stash_job:wait()
      if not is_active_session(session) then
        return
      end
      state.job = nil
      state.head = head_result.code == 0 and (head_result.stdout or ''):gsub('%s+$', '') or '(unknown)'
      state.merge = merge_result.code == 0 and (merge_result.stdout or ''):gsub('%s+$', '') or '(none)'

      if result.code ~= 0 then
        common_ui.set_buffer_lines(state.log_buf, { '-- Failed to load git status --', result.stderr or '' })
        status_ui.update_statusline(state, false)
        return
      end

      local grouped = core.parse_status_grouped(result.stdout or '')
      local commits = {}
      for _, key in ipairs(status_ui.section_order) do
        local files = grouped[key]
        if #files > 0 then
          local section = {
            section = key,
            files = files,
            expanded = true,
            expanded_dirs = {},
            tree_opts = status_ui.make_tree_opts(key),
          }
          tree.expand_all_dirs(section)
          commits[#commits + 1] = section
        end
      end

      local stashes = {}
      if stash_result.code == 0 and stash_result.stdout and stash_result.stdout ~= '' then
        for line in stash_result.stdout:gmatch('[^\n]+') do
          local ref, msg = line:match('^(.-)%z(.*)$')
          if ref then
            stashes[#stashes + 1] = { ref = ref, message = msg }
          end
        end
      end

      for _, s in ipairs(stashes) do
        commits[#commits + 1] = {
          section = 'stash',
          stash_label = s.ref .. ': ' .. s.message,
          stash_ref = s.ref,
          files = {},
          files_loaded = false,
          expanded = false,
          expanded_dirs = {},
          tree_opts = status_ui.make_tree_opts('stash'),
        }
      end

      state.commits = commits
      state.stashes = stashes
      status_ui.render(state)
      status_ui.update_statusline(state, false)
    end)
  end)
end

-- ── keymaps ──────────────────────────────────────────────

local function setup_keymaps()
  local opts = { buffer = state.log_buf, nowait = true }
  local preview_scheduler = scheduler.create(function()
    show_file_diff(true)
  end)

  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = state.log_buf,
    callback = function()
      preview_scheduler.request()
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.log_buf,
    once = true,
    callback = preview_scheduler.close,
  })

  vim.keymap.set('n', 'l', activate_item, opts)
  vim.keymap.set('n', '>', activate_item, opts)
  vim.keymap.set('n', '<cr>', activate_item, opts)
  vim.keymap.set('n', 'h', function()
    local item = tree.item_under_cursor(state)
    if item and item.type == 'stash_header' and state.stash_expanded ~= false then
      state.stash_expanded = false
      status_ui.render(state)
      return
    end
    tree.close_parent_node(state)
  end, opts)
  vim.keymap.set('n', '<', function()
    local item = tree.item_under_cursor(state)
    if item and item.type == 'stash_header' and state.stash_expanded ~= false then
      state.stash_expanded = false
      status_ui.render(state)
      return
    end
    tree.close_parent_node(state)
  end, opts)
  vim.keymap.set('n', 'H', function()
    tree.close_commit_node(state)
  end, opts)
  vim.keymap.set('n', 'X', function()
    local item = tree.item_under_cursor(state)
    if item and (item.stash or item.type == 'stash_header') then
      return
    end
    if discard_section() then
      return
    end
    discard_change()
  end, opts)
  vim.keymap.set('n', 'x', function()
    local item = tree.item_under_cursor(state)
    if item and item.type == 'stash_header' then
      return
    end
    discard_change()
  end, opts)
  vim.keymap.set('n', 'A', stage_section, opts)
  vim.keymap.set('n', 'a', function()
    local item = item_under_cursor()
    if not item or item.type ~= 'file' then
      return
    end
    local section, file = get_section_and_file(item)
    if not section or not file then
      return
    end
    if section.section == 'untracked' or section.section == 'unstaged' then
      if not run_git({ 'git', 'add', '--', file.path }, 'Failed to stage file: ') then
        return
      end
      push_undo('stage file', { { type = 'reset_paths', paths = { file.path } } })
      reload_status()
    end
  end, opts)
  vim.keymap.set('n', 'u', undo_last_action, opts)
  vim.keymap.set('n', 'r', function()
    state.preview_key = nil
    load_status()
  end, opts)
  vim.keymap.set('n', '<leader>gs', function()
    state.preview_key = nil
    load_status()
  end, opts)
  vim.keymap.set('n', 'd', function()
    state.diff_changes_only = not state.diff_changes_only
    env_keeper.set('git_status_diff_changes_only', state.diff_changes_only)
    status_ui.update_statusline(state, false)
    vim.notify('Changes only: ' .. (state.diff_changes_only and 'on' or 'off'), vim.log.levels.INFO)
    state.preview_key = nil
    show_file_diff(true)
  end, opts)
  vim.keymap.set('n', 'D', function()
    state.diff_mode = state.diff_mode == 'single' and 'dual' or 'single'
    env_keeper.set('git_status_diff_mode', state.diff_mode)
    status_ui.update_statusline(state, false)
    vim.notify('Diff mode: ' .. state.diff_mode, vim.log.levels.INFO)
    state.preview_key = nil
    show_file_diff(true)
  end, opts)
  vim.keymap.set('n', 'gf', function()
    local item = item_under_cursor()
    if not item or item.type ~= 'file' then
      return
    end
    local _, file = get_section_and_file(item)
    if not file then
      return
    end
    local target_win
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= state.log_win and not diff.is_tracked_diff_window(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        local bt = vim.bo[buf].buftype
        if bt == '' then
          target_win = win
          break
        end
      end
    end
    if target_win then
      vim.api.nvim_set_current_win(target_win)
    else
      vim.cmd('wincmd p')
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(state.repo_root .. '/' .. file.path))
  end, opts)
  vim.keymap.set('n', 'Z', function()
    if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
      return
    end
    local total = vim.o.lines
    local win_height = config.get('git_status', 'win_height')
    local win_height_expanded = config.get('git_status', 'win_height_expanded')
    local threshold = math.floor(total * (win_height + win_height_expanded) / 2)
    local current = vim.api.nvim_win_get_height(state.log_win)
    if current >= threshold then
      vim.api.nvim_win_set_height(state.log_win, math.floor(total * win_height))
    else
      vim.api.nvim_win_set_height(state.log_win, math.floor(total * win_height_expanded))
    end
  end, opts)
  vim.keymap.set('n', '?', function()
    help.show_help('Help', {
      'Git Status Keymaps',
      '',
      '  l/>/<CR> Open node / show diff',
      '  h/<      Fold parent node',
      '  H       Fold section',
      '  d       Toggle changes-only',
      '  D       Toggle diff mode: single / dual',
      '  x       Discard file / Drop stash',
      '  X       Discard section',
      '  u       Undo last git-status action',
      '  a       Stage file',
      '  A       Stage section',
      '  gf      Open file',
      '  Z       Toggle window height',
      '  ?       Show this help',
    })
  end, opts)
end

-- ── show ─────────────────────────────────────────────────

function M.show()
  local start_path = vim.fn.expand('%:p')
  if start_path == '' then
    start_path = vim.fn.getcwd()
  end

  local repo_root = vim.fs.root(start_path, '.git')
  if not repo_root then
    vim.notify('Not in a git repository', vim.log.levels.WARN)
    return
  end

  cleanup()
  state.session = state.session + 1
  state.repo_root = repo_root

  state.log_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.log_buf].buftype = 'nofile'
  vim.bo[state.log_buf].bufhidden = 'wipe'
  vim.bo[state.log_buf].swapfile = false
  vim.bo[state.log_buf].filetype = 'git'
  common_ui.set_buffer_lines(state.log_buf, { '-- Loading git status... --' })

  local height = math.floor(vim.api.nvim_win_get_height(0) * config.get('git_status', 'win_height'))
  vim.cmd('botright split')
  state.log_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.log_win, state.log_buf)
  vim.api.nvim_win_set_height(state.log_win, height)

  setup_keymaps()
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.log_buf,
    once = true,
    callback = cleanup,
  })

  load_status()
end

return M
