local core = require('lu5je0.ext.git.project-log.core')
local diff = require('lu5je0.ext.git.git-status.diff')
local help = require('lu5je0.ext.git.common.help')
local scheduler = require('lu5je0.ext.git.common.scheduler')
local status_ui = require('lu5je0.ext.git.git-status.ui')
local tree = require('lu5je0.ext.git.common.tree')
local common_ui = require('lu5je0.ext.git.common.ui')
local env_keeper = require('lu5je0.misc.env-keeper')

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
  diff_mode = env_keeper.get('git_status_diff_mode', 'single'),
  diff_changes_only = env_keeper.get('git_status_diff_changes_only', false),
  closing_diff_windows = false,
  tree_opts = {},
  render = function(s) status_ui.render(s) end,
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
    local restore_cmd = string.format('git stash store -m %s %s', vim.fn.shellescape(stash_msg), sha)
    local notify_msg = string.format('Dropped %s. Restore: %s', commit.stash_ref, restore_cmd)
    discard_log(notify_msg)
    vim.notify(notify_msg, vim.log.levels.INFO)
    state.preview_key = nil
    load_status()
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
    local hash_result = vim.system({ 'git', 'hash-object', '-w', abs_path }, { text = true, cwd = state.repo_root }):wait()
    local blob = (hash_result.stdout or ''):gsub('%s+$', '')
    os.remove(abs_path)
    discard_log(string.format('Deleted %s. Restore: git show %s > %s', abs_path, blob, abs_path))
    vim.notify(string.format('Deleted %s. Restore: git show %s > %s', file.path, blob, file.path), vim.log.levels.INFO)
  elseif section.section == 'unstaged' then
    local hash_result = vim.system({ 'git', 'hash-object', '-w', abs_path }, { text = true, cwd = state.repo_root }):wait()
    local blob = (hash_result.stdout or ''):gsub('%s+$', '')
    vim.system({ 'git', 'checkout', '--', file.path }, { cwd = state.repo_root }):wait()
    discard_log(string.format('Restored %s from index. Undo: git show %s > %s', abs_path, blob, abs_path))
    vim.notify(string.format('Restored %s from index. Undo: git show %s > %s', file.path, blob, file.path), vim.log.levels.INFO)
  elseif section.section == 'staged' then
    vim.system({ 'git', 'reset', 'HEAD', '--', file.path }, { cwd = state.repo_root }):wait()
    discard_log(string.format('Unstaged %s. Restore: git add %s', abs_path, abs_path))
    vim.notify(string.format('Unstaged %s. Restore: git add %s', file.path, file.path), vim.log.levels.INFO)
  end

  state.preview_key = nil
  load_status()
end

local function activate_item()
  if tree.open_node(state) then
    return
  end
  state.preview_key = nil
  show_file_diff()
end

-- ── load stash files ─────────────────────────────────────

local function load_stash_files(session)
  local stashes = state.stashes
  if not stashes or #stashes == 0 then
    return
  end
  local pending = #stashes
  for i, stash in ipairs(stashes) do
    vim.system(
      { 'git', 'stash', 'show', '--name-status', '--find-renames', stash.ref },
      { text = true, cwd = state.repo_root },
      function(result)
        vim.schedule(function()
          if not is_active_session(session) then
            return
          end
          local files = core.parse_name_status(result.stdout)
          stashes[i].files = files
          pending = pending - 1
          if pending == 0 then
            for _, s in ipairs(stashes) do
              state.commits[#state.commits + 1] = {
                section = 'stash',
                stash_label = s.ref .. ': ' .. s.message,
                stash_ref = s.ref,
                files = s.files or {},
                expanded = false,
                expanded_dirs = {},
                tree_opts = status_ui.make_tree_opts('stash'),
              }
            end
            status_ui.render(state)
          end
        end)
      end
    )
  end
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

      state.commits = commits
      state.stashes = stashes
      status_ui.render(state)
      status_ui.update_statusline(state, false)

      if #stashes > 0 then
        load_stash_files(session)
      end
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
    tree.close_parent_node(state)
  end, opts)
  vim.keymap.set('n', '<', function()
    tree.close_parent_node(state)
  end, opts)
  vim.keymap.set('n', 'H', function()
    tree.close_commit_node(state)
  end, opts)
  vim.keymap.set('n', 'X', discard_change, opts)
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
      vim.system({ 'git', 'add', '--', file.path }, { cwd = state.repo_root }):wait()
      state.preview_key = nil
      load_status()
    end
  end, opts)
  vim.keymap.set('n', 'r', function()
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
  vim.keymap.set('n', 'x', function()
    if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
      return
    end
    local total = vim.o.lines
    local threshold = math.floor(total * 0.7)
    local current = vim.api.nvim_win_get_height(state.log_win)
    if current >= threshold then
      vim.api.nvim_win_set_height(state.log_win, math.floor(total * 0.5))
    else
      vim.api.nvim_win_set_height(state.log_win, math.floor(total * 0.9))
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
      '  X       Discard change / Drop stash',
      '  a       Stage file',
      '  gf      Open file',
      '  x       Toggle window height',
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

  local height = math.floor(vim.api.nvim_win_get_height(0) * 0.5)
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
