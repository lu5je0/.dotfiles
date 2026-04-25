local core = require('lu5je0.ext.git.project-log.core')
local help = require('lu5je0.ext.git.common.help')
local scheduler = require('lu5je0.ext.git.common.scheduler')
local tree = require('lu5je0.ext.git.common.tree')
local ui = require('lu5je0.ext.git.common.ui')
local env_keeper = require('lu5je0.misc.env-keeper')

local M = {}

local load_status
local render

local ns_id = vim.api.nvim_create_namespace('git_status')

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
  diff_mode = env_keeper.get('git_status_diff_mode', 'single'),
  diff_changes_only = env_keeper.get('git_status_diff_changes_only', false),
  closing_diff_windows = false,
  render = function(s) render(s) end,
}

-- ── helpers ──────────────────────────────────────────────

local section_labels = {
  untracked = 'Untracked',
  unstaged = 'Unstaged',
  staged = 'Staged',
}

local section_order = { 'untracked', 'unstaged', 'staged' }

local function kill_job(name)
  if state[name] then
    pcall(function() state[name]:kill() end)
    state[name] = nil
  end
end

local function kill_jobs()
  kill_job('job')
  kill_job('diff_job')
  kill_job('diff_job2')
end

-- ── diff window management (same pattern as project-log/diff.lua) ──

local function is_tracked_diff_window(win)
  return win and vim.api.nvim_win_is_valid(win) and vim.w[win].git_status_diff == true
end

local function mark_diff_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.w[win].git_status_diff = true
  end
end

local function close_win(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function close_diff_windows()
  state.closing_diff_windows = true
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_tracked_diff_window(win) then
      close_win(win)
    end
  end
  close_win(state.diff_win2)
  close_win(state.diff_win)
  state.diff_buf = nil
  state.diff_buf2 = nil
  state.diff_win = nil
  state.diff_win2 = nil
  state.closing_diff_windows = false
end

local function is_active_session(session)
  return state.session == session
end

local function cleanup()
  kill_jobs()
  close_diff_windows()
  state.session = state.session + 1
  state.log_buf = nil
  state.log_win = nil
  state.commits = {}
  state.display_items = {}
  state.header_count = 0
  state.preview_key = nil
  state.head = nil
  state.merge = nil
end

local function close_all()
  if state.log_win and vim.api.nvim_win_is_valid(state.log_win) then
    pcall(vim.api.nvim_win_close, state.log_win, true)
  end
  cleanup()
end

-- ── rendering ────────────────────────────────────────────

render = function(state_)
  if not state_.log_buf or not vim.api.nvim_buf_is_valid(state_.log_buf) then
    return
  end

  local lines = {}
  local items = {}

  -- header
  lines[#lines + 1] = 'Head:   ' .. (state_.head or '')
  items[#items + 1] = { type = 'header' }
  lines[#lines + 1] = 'Merge:  ' .. (state_.merge or '')
  items[#items + 1] = { type = 'header' }
  lines[#lines + 1] = ''
  items[#items + 1] = { type = 'header' }
  state_.header_count = #lines

  for commit_idx, commit in ipairs(state_.commits) do
    local label = section_labels[commit.section] or commit.section
    lines[#lines + 1] = string.format('%s (%d)', label, #commit.files)
    items[#items + 1] = { type = 'commit', commit_idx = commit_idx }

    if commit.expanded then
      for _, entry in ipairs(ui.build_file_tree_entries(commit)) do
        lines[#lines + 1] = entry.line
        if entry.type == 'file' then
          items[#items + 1] = { type = 'file', commit_idx = commit_idx, file_idx = entry.file_idx, tree_entry = entry }
        else
          items[#items + 1] = { type = 'dir', commit_idx = commit_idx, dir_path = entry.dir_path, tree_entry = entry }
        end
      end
    end

    lines[#lines + 1] = ''
    items[#items + 1] = { type = 'blank' }
  end

  -- remove trailing blank
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
    table.remove(items)
  end

  ui.set_buffer_lines(state_.log_buf, lines)

  -- highlights
  vim.api.nvim_buf_clear_namespace(state_.log_buf, ns_id, 0, -1)
  for idx, item in ipairs(items) do
    local li = idx - 1
    if item.type == 'header' then
      local line = lines[idx]
      local colon = line:find(':', 1, true)
      if colon then
        vim.api.nvim_buf_add_highlight(state_.log_buf, ns_id, 'Function', li, 0, colon - 1)
        local value_start = line:find('%S', colon + 1)
        if value_start then
          vim.api.nvim_buf_add_highlight(state_.log_buf, ns_id, 'Number', li, value_start - 1, -1)
        end
      end
    elseif item.type == 'commit' then
      vim.api.nvim_buf_add_highlight(state_.log_buf, ns_id, 'Title', li, 0, -1)
    elseif item.tree_entry then
      -- offset = 2 for the "  " prefix we added
      ui.highlight_tree_entry(state_.log_buf, li, item.tree_entry)
    end
  end

  state_.display_items = items
end

local function update_statusline(loading)
  if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
    return
  end
  local mode = string.format('%s%s', state.diff_mode, state.diff_changes_only and ' changes-only' or '')
  if loading then
    vim.wo[state.log_win].statusline = string.format(' %%#Function#Git Status%%* [%%#Special#loading%%*] %%#Comment#%s%%*', mode)
  else
    local total = 0
    for _, c in ipairs(state.commits) do
      total = total + #c.files
    end
    vim.wo[state.log_win].statusline = string.format(' %%#Function#Git Status%%* %%#Number#%d changes%%* %%#Comment#%s%%*', total, mode)
  end
end

-- ── item_under_cursor (wraps tree.lua but skips header/blank) ──

local function item_under_cursor()
  local item = tree.item_under_cursor(state)
  if not item or item.type == 'header' or item.type == 'blank' then
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

-- ── diff ─────────────────────────────────────────────────

local function make_preview_key(section, file)
  if not section or not file then
    return nil
  end
  return table.concat({
    section.section,
    file.status,
    file.old_path or '',
    file.path,
    state.diff_mode,
    tostring(state.diff_changes_only),
  }, '\30')
end

local function has_diff_window()
  return state.diff_win and vim.api.nvim_win_is_valid(state.diff_win)
end

local function set_single_diff_lines(section, file, lines)
  if state.diff_win2 and vim.api.nvim_win_is_valid(state.diff_win2) then
    close_diff_windows()
  end

  if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) and state.diff_buf and vim.api.nvim_buf_is_valid(state.diff_buf) then
    ui.set_buffer_lines(state.diff_buf, lines)
  else
    state.diff_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.diff_buf].buftype = 'nofile'
    vim.bo[state.diff_buf].bufhidden = 'wipe'
    vim.bo[state.diff_buf].swapfile = false
    vim.bo[state.diff_buf].filetype = 'git'
    ui.set_buffer_lines(state.diff_buf, lines)

    vim.api.nvim_set_current_win(state.log_win)
    vim.cmd('vsplit')
    state.diff_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.diff_win, state.diff_buf)
    mark_diff_window(state.diff_win)
    vim.api.nvim_set_current_win(state.log_win)
  end

  local label = section_labels[section.section] or section.section
  vim.wo[state.diff_win].statusline = string.format(' %%#Function#Diff%%* %%#Number#%s%%* %%#Comment#%s%%*', label, file.path)
end

local function filetype_for_path(path)
  local ft = path and vim.filetype.match({ filename = path }) or nil
  return ft ~= '' and ft or nil
end

local function load_lines_async(rev, path, callback)
  if not path then
    vim.schedule(function() callback({}) end)
    return nil
  end
  return vim.system({ 'git', 'show', rev .. ':' .. path }, { text = true, cwd = state.repo_root }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback({})
        return
      end
      local text = result.stdout or ''
      local lines = vim.split(text, '\n', { plain = true })
      if #lines > 0 and lines[#lines] == '' then
        table.remove(lines)
      end
      callback(lines)
    end)
  end)
end

local function load_worktree_lines(path, callback)
  vim.schedule(function()
    local ok, lines = pcall(vim.fn.readfile, state.repo_root .. '/' .. path)
    callback(ok and lines or {})
  end)
  return nil
end

local function show_single_diff(section, file)
  kill_job('diff_job')
  kill_job('diff_job2')

  if section.section == 'untracked' then
    load_worktree_lines(file.path, function(lines)
      local Block = require('lu5je0.ext.git.line-log.block')
      local diff_opts = state.diff_changes_only and { ctxlen = 3 } or nil
      set_single_diff_lines(section, file, Block.generate_diff(nil, Block.new(lines, 1, #lines), nil, file.path, diff_opts))
    end)
    return
  end

  local args
  local unified = state.diff_changes_only and '--unified=3' or '--unified=999999'
  if section.section == 'staged' then
    args = { 'git', 'diff', '--cached', unified, '--no-ext-diff', '--no-color', '--', file.path }
  else
    args = { 'git', 'diff', unified, '--no-ext-diff', '--no-color', '--', file.path }
  end

  state.diff_job = vim.system(args, { text = true, cwd = state.repo_root }, function(result)
    vim.schedule(function()
      state.diff_job = nil
      local lines
      if result.code == 0 and result.stdout and result.stdout ~= '' then
        lines = vim.split(result.stdout, '\n', { plain = true })
        if #lines > 0 and lines[#lines] == '' then
          table.remove(lines)
        end
      else
        lines = { '-- No diff --' }
      end
      set_single_diff_lines(section, file, lines)
    end)
  end)
end

local function show_dual_diff(section, file)
  kill_job('diff_job')
  kill_job('diff_job2')

  local old_lines, new_lines

  local function maybe_show()
    if not old_lines or not new_lines then
      return
    end
    state.diff_job = nil
    state.diff_job2 = nil
    close_diff_windows()

    local Block = require('lu5je0.ext.git.line-log.block')
    local old_block = Block.new(old_lines, 1, #old_lines)
    local new_block = Block.new(new_lines, 1, #new_lines)

    state.diff_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.diff_buf].buftype = 'nofile'
    vim.bo[state.diff_buf].bufhidden = 'wipe'
    vim.bo[state.diff_buf].swapfile = false
    local old_ft = filetype_for_path(file.path)
    if old_ft then vim.bo[state.diff_buf].filetype = old_ft end
    ui.set_buffer_lines(state.diff_buf, old_block:get_content())

    vim.api.nvim_set_current_win(state.log_win)
    vim.cmd('vsplit')
    state.diff_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.diff_win, state.diff_buf)
    mark_diff_window(state.diff_win)
    vim.wo[state.diff_win].diff = true
    vim.wo[state.diff_win].scrollbind = true
    vim.wo[state.diff_win].wrap = false

    state.diff_buf2 = vim.api.nvim_create_buf(false, true)
    vim.bo[state.diff_buf2].buftype = 'nofile'
    vim.bo[state.diff_buf2].bufhidden = 'wipe'
    vim.bo[state.diff_buf2].swapfile = false
    local new_ft = filetype_for_path(file.path)
    if new_ft then vim.bo[state.diff_buf2].filetype = new_ft end
    ui.set_buffer_lines(state.diff_buf2, new_block:get_content())

    vim.cmd('vsplit')
    state.diff_win2 = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.diff_win2, state.diff_buf2)
    mark_diff_window(state.diff_win2)
    vim.wo[state.diff_win2].diff = true
    vim.wo[state.diff_win2].scrollbind = true
    vim.wo[state.diff_win2].wrap = false

    local closing = false
    for _, buf in ipairs({ state.diff_buf, state.diff_buf2 }) do
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        once = true,
        callback = function()
          if state.closing_diff_windows or closing then return end
          closing = true
          close_diff_windows()
        end,
      })
    end

    vim.wo[state.diff_win].foldmethod = 'diff'
    vim.wo[state.diff_win].foldlevel = 0
    vim.wo[state.diff_win].foldenable = state.diff_changes_only
    vim.wo[state.diff_win2].foldmethod = 'diff'
    vim.wo[state.diff_win2].foldlevel = 0
    vim.wo[state.diff_win2].foldenable = state.diff_changes_only

    local label = section_labels[section.section] or section.section
    vim.wo[state.diff_win].statusline = string.format('%%#Comment#%s (old) %s%%*', label, file.path)
    vim.wo[state.diff_win2].statusline = string.format('%%#Number#%s%%* %%#Comment#%s%%*', label, file.path)
    vim.api.nvim_set_current_win(state.log_win)
  end

  if section.section == 'untracked' then
    old_lines = {}
    load_worktree_lines(file.path, function(lines)
      new_lines = lines
      maybe_show()
    end)
    return
  end

  if section.section == 'staged' then
    -- old = HEAD, new = index
    state.diff_job = load_lines_async('HEAD', file.path, function(lines)
      old_lines = lines
      maybe_show()
    end)
    state.diff_job2 = vim.system({ 'git', 'show', ':' .. file.path }, { text = true, cwd = state.repo_root }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          local text = result.stdout or ''
          new_lines = vim.split(text, '\n', { plain = true })
          if #new_lines > 0 and new_lines[#new_lines] == '' then table.remove(new_lines) end
        else
          new_lines = {}
        end
        maybe_show()
      end)
    end)
  else
    -- unstaged: old = index, new = worktree
    state.diff_job = vim.system({ 'git', 'show', ':' .. file.path }, { text = true, cwd = state.repo_root }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          local text = result.stdout or ''
          old_lines = vim.split(text, '\n', { plain = true })
          if #old_lines > 0 and old_lines[#old_lines] == '' then table.remove(old_lines) end
        else
          old_lines = {}
        end
        maybe_show()
      end)
    end)
    load_worktree_lines(file.path, function(lines)
      new_lines = lines
      maybe_show()
    end)
  end
end

local function show_file_diff(auto_preview)
  if auto_preview and not has_diff_window() then
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
  local preview_key = make_preview_key(section, file)
  if state.preview_key == preview_key then
    return true
  end
  state.preview_key = preview_key
  if state.diff_mode == 'dual' then
    show_dual_diff(section, file)
  else
    show_single_diff(section, file)
  end
  return true
end

-- ── X discard ────────────────────────────────────────────

local function discard_change()
  local item = item_under_cursor()
  if not item or item.type ~= 'file' then
    return
  end
  local section, file = get_section_and_file(item)
  if not section or not file then
    return
  end

  local abs_path = state.repo_root .. '/' .. file.path

  if section.section == 'untracked' then
    -- hash the file content before deleting so we can show a restore command
    local hash_result = vim.system({ 'git', 'hash-object', '-w', abs_path }, { text = true, cwd = state.repo_root }):wait()
    local blob = (hash_result.stdout or ''):gsub('%s+$', '')
    os.remove(abs_path)
    vim.notify(string.format('Deleted %s. To restore: git show %s > %s', file.path, blob, file.path), vim.log.levels.INFO)
  elseif section.section == 'unstaged' then
    local hash_result = vim.system({ 'git', 'hash-object', '-w', abs_path }, { text = true, cwd = state.repo_root }):wait()
    local blob = (hash_result.stdout or ''):gsub('%s+$', '')
    vim.system({ 'git', 'checkout', '--', file.path }, { cwd = state.repo_root }):wait()
    vim.notify(string.format('Restored %s from index. To undo: git show %s > %s', file.path, blob, file.path), vim.log.levels.INFO)
  elseif section.section == 'staged' then
    vim.system({ 'git', 'reset', 'HEAD', '--', file.path }, { cwd = state.repo_root }):wait()
    vim.notify(string.format('Unstaged %s. To restore: git add %s', file.path, file.path), vim.log.levels.INFO)
  end

  -- refresh
  state.preview_key = nil
  load_status()
end

-- ── activate ─────────────────────────────────────────────

local function activate_item()
  if tree.open_node(state) then
    return
  end
  state.preview_key = nil
  show_file_diff()
end

-- ── load status ──────────────────────────────────────────

load_status = function()
  local session = state.session
  update_statusline(true)

  -- get branch info
  local head_job = vim.system({ 'git', 'rev-parse', '--abbrev-ref', 'HEAD' }, { text = true, cwd = state.repo_root })
  local merge_job = vim.system({ 'git', 'rev-parse', '--abbrev-ref', '@{upstream}' }, { text = true, cwd = state.repo_root })

  state.job = vim.system({
    'git', 'status', '--porcelain=v1', '-z', '--untracked-files=all',
  }, { text = true, cwd = state.repo_root }, function(result)
    vim.schedule(function()
      local head_result = head_job:wait()
      local merge_result = merge_job:wait()
      if not is_active_session(session) then
        return
      end
      state.job = nil
      state.head = head_result.code == 0 and (head_result.stdout or ''):gsub('%s+$', '') or '(unknown)'
      state.merge = merge_result.code == 0 and (merge_result.stdout or ''):gsub('%s+$', '') or '(none)'

      if result.code ~= 0 then
        ui.set_buffer_lines(state.log_buf, { '-- Failed to load git status --', result.stderr or '' })
        update_statusline(false)
        return
      end

      local grouped = core.parse_status_grouped(result.stdout or '')
      local commits = {}
      for _, key in ipairs(section_order) do
        local files = grouped[key]
        if #files > 0 then
          local section = {
            section = key,
            files = files,
            expanded = true,
            expanded_dirs = {},
          }
          tree.expand_all_dirs(section)
          commits[#commits + 1] = section
        end
      end

      state.commits = commits
      render(state)
      update_statusline(false)
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
  vim.keymap.set('n', 'r', function()
    state.preview_key = nil
    load_status()
  end, opts)
  vim.keymap.set('n', 'd', function()
    state.diff_changes_only = not state.diff_changes_only
    env_keeper.set('git_status_diff_changes_only', state.diff_changes_only)
    update_statusline(false)
    vim.notify('Changes only: ' .. (state.diff_changes_only and 'on' or 'off'), vim.log.levels.INFO)
    state.preview_key = nil
    show_file_diff(true)
  end, opts)
  vim.keymap.set('n', 'D', function()
    state.diff_mode = state.diff_mode == 'single' and 'dual' or 'single'
    env_keeper.set('git_status_diff_mode', state.diff_mode)
    update_statusline(false)
    vim.notify('Diff mode: ' .. state.diff_mode, vim.log.levels.INFO)
    state.preview_key = nil
    show_file_diff(true)
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
      '  X       Discard change',
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
  ui.set_buffer_lines(state.log_buf, { '-- Loading git status... --' })

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
