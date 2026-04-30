local Block = require('lu5je0.ext.git.line-log.block')
local ui = require('lu5je0.ext.git.common.ui')
local config = require('lu5je0.ext.git.config')

local M = {}

local function close_win(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function is_tracked_diff_window(win)
  return win and vim.api.nvim_win_is_valid(win) and vim.w[win].git_project_log_diff == true
end

local function mark_diff_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.w[win].git_project_log_diff = true
  end
end

local function reset_diff_state(state)
  state.diff_buf = nil
  state.diff_buf2 = nil
  state.diff_win = nil
  state.diff_win2 = nil
end

function M.close_windows(state)
  state.closing_diff_windows = true
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_tracked_diff_window(win) then
      close_win(win)
    end
  end
  close_win(state.diff_win2)
  close_win(state.diff_win)
  reset_diff_state(state)
  state.closing_diff_windows = false
end

function M.kill_jobs(state)
  for _, name in ipairs({ 'diff_job', 'diff_job2' }) do
    if state[name] then
      pcall(function()
        state[name]:kill()
      end)
      state[name] = nil
    end
  end
end

local function load_lines_async(state, rev, path, callback)
  if not path then
    vim.schedule(function()
      callback({})
    end)
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

local function load_worktree_lines_async(state, path, callback)
  vim.schedule(function()
    local ok, lines = pcall(vim.fn.readfile, state.repo_root .. '/' .. path)
    callback(ok and lines or {})
  end)
  return nil
end

local function filetype_for_path(path)
  local ft = path and vim.filetype.match({ filename = path }) or nil
  return ft ~= '' and ft or nil
end

local function set_single_diff_lines(state, commit, file, lines)
  if state.diff_win2 and vim.api.nvim_win_is_valid(state.diff_win2) then
    M.close_windows(state)
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
    vim.api.nvim_win_set_width(state.log_win, config.log_width)
    vim.api.nvim_set_current_win(state.log_win)
  end

  local label = commit.local_change and 'local' or commit.short_hash
  vim.wo[state.diff_win].statusline = string.format(' %%#Function#Diff%%* %%#Number#%s%%* %%#Comment#%s%%*', label, file.path)
end

local function show_local_single_diff(state, commit, file)
  M.kill_jobs(state)

  if file.status == '??' then
    load_worktree_lines_async(state, file.path, function(lines)
      local diff_opts = state.diff_changes_only and { ctxlen = 3 } or nil
      set_single_diff_lines(state, commit, file, Block.generate_diff(nil, Block.new(lines, 1, #lines), nil, file.path, diff_opts))
    end)
    return
  end

  local diff_path = file.status:sub(1, 1) == 'D' and (file.old_path or file.path) or file.path
  local unified = state.diff_changes_only and '--unified=3' or '--unified=999999'
  state.diff_job = vim.system({
    'git',
    'diff',
    unified,
    '--no-ext-diff',
    '--no-color',
    'HEAD',
    '--',
    diff_path,
  }, { text = true, cwd = state.repo_root }, function(result)
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
      set_single_diff_lines(state, commit, file, lines)
    end)
  end)
end

function M.show_single(state, commit, file)
  if commit.local_change then
    show_local_single_diff(state, commit, file)
    return
  end

  M.kill_jobs(state)
  local diff_path = file.status:sub(1, 1) == 'D' and (file.old_path or file.path) or file.path
  local unified = state.diff_changes_only and '--unified=3' or '--unified=999999'
  state.diff_job = vim.system({
    'git',
    'show',
    unified,
    '--format=',
    '--find-renames',
    '--find-copies',
    commit.hash,
    '--',
    diff_path,
  }, { text = true, cwd = state.repo_root }, function(result)
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

      set_single_diff_lines(state, commit, file, lines)
    end)
  end)
end

function M.show_dual(state, commit, file)
  M.kill_jobs(state)
  local old_path = file.old_path or file.path
  local new_path = file.path
  local old_lines, new_lines

  local function maybe_show()
    if old_lines and new_lines then
      M.show_dual_file(state, commit, file, old_lines, new_lines)
    end
  end

  if commit.local_change and file.status == '??' then
    old_lines = {}
  else
    local old_rev = commit.local_change and 'HEAD' or (commit.hash .. '^')
    state.diff_job = load_lines_async(state, old_rev, old_path, function(lines)
      old_lines = lines
      maybe_show()
    end)
  end

  if commit.local_change then
    state.diff_job2 = load_worktree_lines_async(state, new_path, function(lines)
      new_lines = lines
      maybe_show()
    end)
    maybe_show()
    return
  end

  state.diff_job2 = load_lines_async(state, commit.hash, new_path, function(lines)
    new_lines = lines
    maybe_show()
  end)
end

function M.show_dual_file(state, commit, file, old_lines, new_lines)
  state.diff_job = nil
  state.diff_job2 = nil
  M.close_windows(state)

  local old_block = Block.new(old_lines, 1, #old_lines)
  local new_block = Block.new(new_lines, 1, #new_lines)
  local old_file = file.old_path or file.path
  local new_file = file.path

  state.diff_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.diff_buf].buftype = 'nofile'
  vim.bo[state.diff_buf].bufhidden = 'wipe'
  vim.bo[state.diff_buf].swapfile = false
  local old_ft = filetype_for_path(old_file)
  if old_ft then
    vim.bo[state.diff_buf].filetype = old_ft
  end
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
  local new_ft = filetype_for_path(new_file)
  if new_ft then
    vim.bo[state.diff_buf2].filetype = new_ft
  end
  ui.set_buffer_lines(state.diff_buf2, new_block:get_content())

  vim.cmd('vsplit')
  state.diff_win2 = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.diff_win2, state.diff_buf2)
  mark_diff_window(state.diff_win2)
  vim.wo[state.diff_win2].diff = true
  vim.wo[state.diff_win2].scrollbind = true
  vim.wo[state.diff_win2].wrap = false

  local remaining = vim.o.columns - config.log_width
  vim.api.nvim_win_set_width(state.log_win, config.log_width)
  vim.api.nvim_win_set_width(state.diff_win, math.floor(remaining / 2))
  vim.api.nvim_win_set_width(state.diff_win2, math.floor(remaining / 2))

  local closing = false
  for _, buf in ipairs({ state.diff_buf, state.diff_buf2 }) do
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      once = true,
      callback = function()
        if state.closing_diff_windows then
          return
        end
        if closing then
          return
        end
        closing = true
        M.close_windows(state)
      end,
    })
  end

  vim.wo[state.diff_win].foldmethod = 'diff'
  vim.wo[state.diff_win].foldlevel = 0
  vim.wo[state.diff_win].foldenable = state.diff_changes_only
  vim.wo[state.diff_win2].foldmethod = 'diff'
  vim.wo[state.diff_win2].foldlevel = 0
  vim.wo[state.diff_win2].foldenable = state.diff_changes_only

  if commit.local_change then
    vim.wo[state.diff_win].statusline = string.format('%%#Comment#HEAD %s%%*', old_file)
    vim.wo[state.diff_win2].statusline = string.format('%%#Number#local%%* %%#Comment#%s%%*', new_file)
  else
    vim.wo[state.diff_win].statusline = string.format('%%#Comment#%s^ %s%%*', commit.short_hash, old_file)
    vim.wo[state.diff_win2].statusline = string.format('%%#Number#%s%%* %%#Comment#%s%%*', commit.short_hash, new_file)
  end
  vim.api.nvim_set_current_win(state.log_win)
end

return M
