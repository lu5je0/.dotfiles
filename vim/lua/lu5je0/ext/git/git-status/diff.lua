local Block = require('lu5je0.ext.git.line-log.block')
local common_ui = require('lu5je0.ext.git.common.ui')

local M = {}

local section_labels = {
  untracked = 'Untracked',
  unstaged = 'Unstaged',
  staged = 'Staged',
}

-- ── diff window management ───────────────────────────────

local function close_win(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

function M.is_tracked_diff_window(win)
  return win and vim.api.nvim_win_is_valid(win) and vim.w[win].git_status_diff == true
end

local function mark_diff_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.w[win].git_status_diff = true
  end
end

function M.close_windows(state)
  state.closing_diff_windows = true
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if M.is_tracked_diff_window(win) then
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

function M.has_window(state)
  return state.diff_win and vim.api.nvim_win_is_valid(state.diff_win)
end

function M.kill_jobs(state)
  for _, name in ipairs({ 'diff_job', 'diff_job2' }) do
    if state[name] then
      pcall(function() state[name]:kill() end)
      state[name] = nil
    end
  end
end

-- ── helpers ──────────────────────────────────────────────

local function filetype_for_path(path)
  local ft = path and vim.filetype.match({ filename = path }) or nil
  return ft ~= '' and ft or nil
end

local function load_lines_async(state, rev, path, callback)
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

local function load_worktree_lines(state, path, callback)
  vim.schedule(function()
    local ok, lines = pcall(vim.fn.readfile, state.repo_root .. '/' .. path)
    callback(ok and lines or {})
  end)
  return nil
end

local function set_single_diff_lines(state, section, file, lines)
  if state.diff_win2 and vim.api.nvim_win_is_valid(state.diff_win2) then
    M.close_windows(state)
  end

  if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) and state.diff_buf and vim.api.nvim_buf_is_valid(state.diff_buf) then
    common_ui.set_buffer_lines(state.diff_buf, lines)
  else
    state.diff_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.diff_buf].buftype = 'nofile'
    vim.bo[state.diff_buf].bufhidden = 'wipe'
    vim.bo[state.diff_buf].swapfile = false
    vim.bo[state.diff_buf].filetype = 'git'
    common_ui.set_buffer_lines(state.diff_buf, lines)

    vim.api.nvim_set_current_win(state.log_win)
    vim.cmd('vsplit')
    state.diff_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.diff_win, state.diff_buf)
    mark_diff_window(state.diff_win)
    vim.api.nvim_win_set_width(state.log_win, math.floor(vim.o.columns / 5))
    vim.api.nvim_set_current_win(state.log_win)
  end

  local diff_label = section.stash_label or section_labels[section.section] or section.section
  vim.wo[state.diff_win].statusline = string.format(' %%#Function#Diff%%* %%#Number#%s%%* %%#Comment#%s%%*', diff_label, file.path)
end

-- ── preview key ──────────────────────────────────────────

function M.make_preview_key(state, section, file)
  if not section or not file then
    return nil
  end
  return table.concat({
    section.section,
    section.stash_ref or '',
    file.status,
    file.old_path or '',
    file.path,
    state.diff_mode,
    tostring(state.diff_changes_only),
  }, '\30')
end

-- ── single diff ──────────────────────────────────────────

function M.show_single(state, section, file)
  M.kill_jobs(state)

  if section.section == 'untracked' then
    load_worktree_lines(state, file.path, function(lines)
      local diff_opts = state.diff_changes_only and { ctxlen = 3 } or nil
      set_single_diff_lines(state, section, file, Block.generate_diff(nil, Block.new(lines, 1, #lines), nil, file.path, diff_opts))
    end)
    return
  end

  local args
  local unified = state.diff_changes_only and '--unified=3' or '--unified=999999'
  if section.section == 'staged' then
    args = { 'git', 'diff', '--cached', unified, '--no-ext-diff', '--no-color', '--', file.path }
  elseif section.section == 'stash' then
    args = { 'git', 'diff', section.stash_ref .. '^', section.stash_ref, unified, '--no-ext-diff', '--no-color', '--', file.path }
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
      set_single_diff_lines(state, section, file, lines)
    end)
  end)
end

-- ── dual diff ────────────────────────────────────────────

function M.show_dual(state, section, file)
  M.kill_jobs(state)

  local old_lines, new_lines

  local function maybe_show()
    if not old_lines or not new_lines then
      return
    end
    state.diff_job = nil
    state.diff_job2 = nil
    M.close_windows(state)

    local old_block = Block.new(old_lines, 1, #old_lines)
    local new_block = Block.new(new_lines, 1, #new_lines)

    state.diff_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.diff_buf].buftype = 'nofile'
    vim.bo[state.diff_buf].bufhidden = 'wipe'
    vim.bo[state.diff_buf].swapfile = false
    local old_ft = filetype_for_path(file.path)
    if old_ft then vim.bo[state.diff_buf].filetype = old_ft end
    common_ui.set_buffer_lines(state.diff_buf, old_block:get_content())

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
    common_ui.set_buffer_lines(state.diff_buf2, new_block:get_content())

    vim.cmd('vsplit')
    state.diff_win2 = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.diff_win2, state.diff_buf2)
    mark_diff_window(state.diff_win2)
    vim.wo[state.diff_win2].diff = true
    vim.wo[state.diff_win2].scrollbind = true
    vim.wo[state.diff_win2].wrap = false

    local fifth = math.floor(vim.o.columns / 5)
    vim.api.nvim_win_set_width(state.log_win, fifth)
    vim.api.nvim_win_set_width(state.diff_win, fifth * 2)
    vim.api.nvim_win_set_width(state.diff_win2, fifth * 2)

    local closing = false
    for _, buf in ipairs({ state.diff_buf, state.diff_buf2 }) do
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        once = true,
        callback = function()
          if state.closing_diff_windows or closing then return end
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

    local dual_label = section.stash_label or section_labels[section.section] or section.section
    vim.wo[state.diff_win].statusline = string.format('%%#Comment#%s (old) %s%%*', dual_label, file.path)
    vim.wo[state.diff_win2].statusline = string.format('%%#Number#%s%%* %%#Comment#%s%%*', dual_label, file.path)
    vim.api.nvim_set_current_win(state.log_win)
  end

  if section.section == 'untracked' then
    old_lines = {}
    load_worktree_lines(state, file.path, function(lines)
      new_lines = lines
      maybe_show()
    end)
    return
  end

  if section.section == 'stash' then
    local ref = section.stash_ref
    state.diff_job = load_lines_async(state, ref .. '^', file.path, function(lines)
      old_lines = lines
      maybe_show()
    end)
    state.diff_job2 = load_lines_async(state, ref, file.path, function(lines)
      new_lines = lines
      maybe_show()
    end)
    return
  end

  if section.section == 'staged' then
    state.diff_job = load_lines_async(state, 'HEAD', file.path, function(lines)
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
    load_worktree_lines(state, file.path, function(lines)
      new_lines = lines
      maybe_show()
    end)
  end
end

return M
