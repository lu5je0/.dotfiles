local core = require('lu5je0.ext.git.project-log.core')
local diff = require('lu5je0.ext.git.git-status.diff')
local help = require('lu5je0.ext.git.common.help')
local scheduler = require('lu5je0.ext.git.common.scheduler')
local status_ui = require('lu5je0.ext.git.git-status.ui')
local tree = require('lu5je0.ext.git.common.tree')
local common_ui = require('lu5je0.ext.git.common.ui')
local env_keeper = require('lu5je0.misc.env-keeper')
local config = require('lu5je0.ext.git.config')
local git_ops = require('lu5je0.ext.git.common.git-ops')

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

-- The synthetic `changes` section bundles staged/unstaged/untracked rows
-- together. For diff preview we still want the right backend per file,
-- so derive an effective section view based on the file's xy.
--   purpose == 'diff' : in Changes the diff should always show HEAD↔worktree
--                       (or untracked → empty↔worktree); ignore staged/unstaged
--                       split so MM rows aren't reduced to "post-stage delta"
--   purpose == 'op'   : per-file backend for stage/discard (untracked /
--                       unstaged / staged)
local function effective_section_for_file(section, file, purpose)
  if not section or section.section ~= 'changes' or not file then
    return section
  end
  purpose = purpose or 'op'
  local backend
  if file.x == '?' then
    backend = 'untracked'
  elseif purpose == 'diff' then
    backend = 'worktree'
  elseif file.y and file.y ~= ' ' then
    backend = 'unstaged'
  else
    backend = 'staged'
  end
  return {
    section = backend,
    files = section.files,
    expanded = section.expanded,
    expanded_dirs = section.expanded_dirs,
    tree_opts = section.tree_opts,
  }
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
  local effective = effective_section_for_file(section, file, 'diff')
  local preview_key = diff.make_preview_key(state, effective, file)
  if state.preview_key == preview_key then
    return true
  end
  state.preview_key = preview_key
  if state.diff_mode == 'dual' then
    diff.show_dual(state, effective, file)
  else
    diff.show_single(state, effective, file)
  end
  return true
end

-- ── actions ──────────────────────────────────────────────

local log_batch = git_ops.log_batch

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
  return git_ops.run_git(args, error_prefix, state.repo_root)
end

local function hash_file(abs_path, write)
  return git_ops.hash_file(abs_path, write, state.repo_root)
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
  git_ops.push_undo(state.undo_stack, label, ops)
end

local function undo_last_action()
  git_ops.undo_last_action(state.undo_stack, state.repo_root, reload_status)
end

local function stage_section()
  local section = get_non_stash_section(item_under_cursor())
  if not section then
    return
  end

  local stage_files
  if section.section == 'changes' then
    stage_files = {}
    for _, f in ipairs(section.files or {}) do
      local x = f.x
      local y = f.y
      -- Untracked or any unstaged side change wants `git add`.
      if x == '?' or (y and y ~= ' ' and y ~= '?') then
        stage_files[#stage_files + 1] = f
      end
    end
    if #stage_files == 0 then
      vim.notify('Already staged', vim.log.levels.INFO)
      return
    end
  elseif section.section == 'untracked' or section.section == 'unstaged' then
    stage_files = section.files
  else
    vim.notify('Already staged', vim.log.levels.INFO)
    return
  end

  local args = append_paths(git_path_args('git', 'add'), stage_files)
  local count = path_count(args)
  if count == 0 then
    return
  end
  if not run_git(args, 'Failed to stage section: ') then
    return
  end
  push_undo('staged', { { type = 'reset_paths', paths = file_paths(stage_files) } })
  log_batch('staged', section.section, count, function(write)
    for _, file in ipairs(stage_files) do
      local abs_path = state.repo_root .. '/' .. file.path
      write(string.format('Staged %s. Restore: git reset HEAD -- %s', abs_path, abs_path))
    end
  end)
  local msg
  if section.section == 'untracked' then
    msg = string.format('Tracked %d files', count)
  elseif section.section == 'changes' then
    msg = string.format('Staged %d changes', count)
  else
    msg = string.format('Staged %d files', count)
  end
  vim.notify(msg, vim.log.levels.INFO)
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
    -- batch hash-object -w for all untracked files
    local abs_paths = {}
    for _, file in ipairs(files) do
      abs_paths[#abs_paths + 1] = state.repo_root .. '/' .. file.path
    end
    local stdin = table.concat(abs_paths, '\n')
    local result = vim.system({ 'git', 'hash-object', '-w', '--stdin-paths' }, { text = true, cwd = state.repo_root, stdin = stdin }):wait()
    if result.code ~= 0 then
      vim.notify('Failed to hash files: ' .. (result.stderr or ''), vim.log.levels.ERROR)
      return true
    end
    local blobs = {}
    for line in (result.stdout or ''):gmatch('[^\n]+') do
      blobs[#blobs + 1] = line
    end
    if #blobs ~= #files then
      vim.notify('Hash mismatch: expected ' .. #files .. ' blobs, got ' .. #blobs, vim.log.levels.ERROR)
      return true
    end
    local restore_files = {}
    log_batch('removed_untracked', 'untracked', #files, function(write)
      for i, file in ipairs(files) do
        local abs_path = abs_paths[i]
        local blob = blobs[i]
        restore_files[#restore_files + 1] = { path = file.path, blob = blob, expected_absent = true }
        os.remove(abs_path)
        write(string.format('Deleted %s. Restore: git show %s > %s', abs_path, blob, abs_path))
      end
    end)
    push_undo('removed untracked', { { type = 'restore_blobs', files = restore_files } })
    vim.notify(string.format('Removed %d untracked files', #files), vim.log.levels.INFO)
  elseif section.section == 'unstaged' then
    -- batch hash-object -w for all existing files (save blobs for undo)
    local existing_files = {}
    local existing_indices = {}
    for i, file in ipairs(files) do
      local abs_path = state.repo_root .. '/' .. file.path
      if vim.uv.fs_stat(abs_path) then
        existing_files[#existing_files + 1] = abs_path
        existing_indices[#existing_indices + 1] = i
      end
    end
    local pre_blobs = {}
    if #existing_files > 0 then
      local stdin = table.concat(existing_files, '\n')
      local result = vim.system({ 'git', 'hash-object', '-w', '--stdin-paths' }, { text = true, cwd = state.repo_root, stdin = stdin }):wait()
      if result.code ~= 0 then
        vim.notify('Failed to hash files: ' .. (result.stderr or ''), vim.log.levels.ERROR)
        return true
      end
      local idx = 1
      for line in (result.stdout or ''):gmatch('[^\n]+') do
        pre_blobs[existing_indices[idx]] = line
        idx = idx + 1
      end
    end

    -- batch git checkout for all files
    local checkout_args = append_paths(git_path_args('git', 'checkout'), files)
    if not run_git(checkout_args, 'Failed to restore files: ') then
      return true
    end

    -- batch hash-object for post-checkout state (expected blobs)
    local post_paths = {}
    for _, file in ipairs(files) do
      post_paths[#post_paths + 1] = state.repo_root .. '/' .. file.path
    end
    local post_result = vim.system({ 'git', 'hash-object', '--stdin-paths' }, { text = true, cwd = state.repo_root, stdin = table.concat(post_paths, '\n') }):wait()
    if post_result.code ~= 0 then
      vim.notify('Failed to hash files: ' .. (post_result.stderr or ''), vim.log.levels.ERROR)
      return true
    end
    local expected_blobs = {}
    local idx = 1
    for line in (post_result.stdout or ''):gmatch('[^\n]+') do
      expected_blobs[idx] = line
      idx = idx + 1
    end

    for i = 1, #files do
      local b = expected_blobs[i]
      if not b or b == '' then
        return true
      end
    end

    local restore_files = {}
    log_batch('reverted', 'unstaged', #files, function(write)
      for i, file in ipairs(files) do
        local abs_path = state.repo_root .. '/' .. file.path
        local blob = pre_blobs[i]
        local expected_blob = expected_blobs[i]
        if blob then
          restore_files[#restore_files + 1] = { path = file.path, blob = blob, expected_blob = expected_blob }
          write(string.format('Restored %s from index. Undo: git show %s > %s', abs_path, blob, abs_path))
        else
          restore_files[#restore_files + 1] = { path = file.path, delete = true, expected_blob = expected_blob }
          write(string.format('Restored %s from index. Undo: delete %s', abs_path, abs_path))
        end
      end
    end)
    push_undo('reverted', { { type = 'restore_blobs', files = restore_files } })
    vim.notify(string.format('Reverted %d files', #files), vim.log.levels.INFO)
  elseif section.section == 'staged' then
    local args = append_paths(git_path_args('git', 'reset', 'HEAD'), files)
    if not run_git(args, 'Failed to unstage section: ') then
      return true
    end
    push_undo('unstaged', { { type = 'add_paths', paths = file_paths(files) } })
    log_batch('unstaged', 'staged', #files, function(write)
      for _, file in ipairs(files) do
        local abs_path = state.repo_root .. '/' .. file.path
        write(string.format('Unstaged %s. Restore: git add %s', abs_path, abs_path))
      end
    end)
    vim.notify(string.format('Unstaged %d files', #files), vim.log.levels.INFO)
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
    log_batch('dropped', 'stash', 1, function(write)
      write(string.format('Dropped %s. Restore: %s', commit.stash_ref, restore_cmd))
    end)
    push_undo('dropped', { { type = 'store_stash', sha = sha, message = stash_msg } })
    vim.notify('Dropped ' .. commit.stash_ref, vim.log.levels.INFO)
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
  section = effective_section_for_file(section, file)

  local abs_path = state.repo_root .. '/' .. file.path

  if section.section == 'untracked' then
    local blob = hash_file(abs_path, true)
    if not blob then
      return
    end
    os.remove(abs_path)
    log_batch('removed_untracked', 'untracked', 1, function(write)
      write(string.format('Deleted %s. Restore: git show %s > %s', abs_path, blob, abs_path))
    end)
    push_undo('removed untracked', {
      { type = 'restore_blobs', files = { { path = file.path, blob = blob, expected_absent = true } } },
    })
    vim.notify('Removed untracked ' .. file.path, vim.log.levels.INFO)
  elseif section.section == 'unstaged' then
    local existed = vim.uv.fs_stat(abs_path) ~= nil
    local blob = existed and hash_file(abs_path, true) or nil
    if not run_git({ 'git', 'checkout', '--', file.path }, 'Failed to restore file: ') then
      return
    end
    local expected_blob = hash_file(abs_path, false)
    if not expected_blob then
      return
    end
    if blob then
      log_batch('reverted', 'unstaged', 1, function(write)
        write(string.format('Restored %s from index. Undo: git show %s > %s', abs_path, blob, abs_path))
      end)
      push_undo('reverted', {
        { type = 'restore_blobs', files = { { path = file.path, blob = blob, expected_blob = expected_blob } } },
      })
      vim.notify('Reverted ' .. file.path, vim.log.levels.INFO)
    else
      log_batch('restored', 'unstaged', 1, function(write)
        write(string.format('Restored %s from index. Undo: delete %s', abs_path, abs_path))
      end)
      push_undo('restored', {
        { type = 'restore_blobs', files = { { path = file.path, delete = true, expected_blob = expected_blob } } },
      })
      vim.notify('Restored ' .. file.path, vim.log.levels.INFO)
    end
  elseif section.section == 'staged' then
    if not run_git({ 'git', 'reset', 'HEAD', '--', file.path }, 'Failed to unstage file: ') then
      return
    end
    log_batch('unstaged', 'staged', 1, function(write)
      write(string.format('Unstaged %s. Restore: git add %s', abs_path, abs_path))
    end)
    push_undo('unstaged', { { type = 'add_paths', paths = { file.path } } })
    vim.notify('Unstaged ' .. file.path, vim.log.levels.INFO)
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
      local prev_expanded = {}
      for _, s in ipairs(state.commits) do
        if s.section and s.section ~= 'stash' then
          prev_expanded[s.section] = s.expanded
        end
      end
      local commits = {}
      local has_changes = grouped.changes and #grouped.changes > 0
      for _, key in ipairs(status_ui.section_order) do
        local files = grouped[key]
        if #files > 0 then
          local default_expanded = key == 'changes' or not has_changes
          local expanded = prev_expanded[key] ~= nil and prev_expanded[key] or default_expanded
          local section = {
            section = key,
            files = files,
            expanded = expanded,
            expanded_dirs = {},
            tree_opts = status_ui.make_tree_opts(key),
          }
          if expanded then
            tree.expand_all_dirs(section)
          end
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
    section = effective_section_for_file(section, file)
    if section.section == 'untracked' or section.section == 'unstaged' then
      if not run_git({ 'git', 'add', '--', file.path }, 'Failed to stage file: ') then
        return
      end
      push_undo('staged', { { type = 'reset_paths', paths = { file.path } } })
      local abs_path = state.repo_root .. '/' .. file.path
      log_batch('staged', section.section, 1, function(write)
        write(string.format('Staged %s. Restore: git reset HEAD -- %s', abs_path, abs_path))
      end)
      local verb = section.section == 'untracked' and 'Tracked' or 'Staged'
      vim.notify(verb .. ' ' .. file.path, vim.log.levels.INFO)
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
  local function open_file_under_cursor()
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
  end
  vim.keymap.set('n', 'gf', open_file_under_cursor, opts)
  vim.keymap.set('n', 'e', open_file_under_cursor, opts)
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
  vim.wo[state.log_win].cursorline = true
  vim.wo[state.log_win].cursorlineopt = 'both'

  setup_keymaps()
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.log_buf,
    once = true,
    callback = cleanup,
  })

  load_status()
end

return M
