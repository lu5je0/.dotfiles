local M = {}

local batch_size = 20
local ns_id = vim.api.nvim_create_namespace('git_line_log')
local spinner = { '󰪞', '󰪟', '󰪠', '󰪡', '󰪢', '󰪣', '󰪤', '󰪥' }

-- 存储当前活跃的 job 和状态
local state = {
  job = nil,
  diff_job = nil,
  log_buf = nil,
  diff_buf = nil,
  log_win = nil,
  diff_win = nil,
  file = nil,
  start_line = nil,
  end_line = nil,
  commit_count = 0,
  spinner_idx = 1,
  spinner_timer = nil,
}

local function update_log_statusline(loading)
  if not vim.api.nvim_win_is_valid(state.log_win) then return end
  local filename = vim.fn.fnamemodify(state.file, ':t')
  local line_range = state.start_line == state.end_line
    and tostring(state.start_line)
    or string.format('%d-%d', state.start_line, state.end_line)
  local status
  if loading then
    status = tostring(state.commit_count) .. ' ' .. spinner[state.spinner_idx]
  else
    status = tostring(state.commit_count)
  end
  vim.wo[state.log_win].statusline = string.format(
    ' %%#Function#Log%%* L%%#Number#%s%%* [%%#Special#%s%%*] %%#Comment#%s%%*',
    line_range, status, filename
  )
end

local function stop_spinner()
  if state.spinner_timer then
    vim.fn.timer_stop(state.spinner_timer)
    state.spinner_timer = nil
  end
end

local function start_spinner()
  stop_spinner()
  state.spinner_idx = 1
  update_log_statusline(true)
  state.spinner_timer = vim.fn.timer_start(50, function()
    if not vim.api.nvim_win_is_valid(state.log_win) then
      stop_spinner()
      return
    end
    state.spinner_idx = (state.spinner_idx % #spinner) + 1
    update_log_statusline(true)
  end, { ['repeat'] = -1 })
end

local function highlight_commit_lines(buf, start_idx, lines)
  for i, line in ipairs(lines) do
    local hash_end = line:find(' ')
    if hash_end then
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'Number', start_idx + i - 1, 0, hash_end - 1)
      local date_start = hash_end
      local date_end = hash_end + 19
      if #line >= date_end then
        vim.api.nvim_buf_add_highlight(buf, ns_id, 'Comment', start_idx + i - 1, date_start, date_end)
      end
    end
  end
end

local function kill_job()
  stop_spinner()
  if state.job then
    pcall(function() state.job:kill() end)
    state.job = nil
  end
  if state.diff_job then
    pcall(function() state.diff_job:kill() end)
    state.diff_job = nil
  end
end

local function cleanup_state()
  kill_job()
  state.log_buf = nil
  state.log_win = nil
  state.diff_buf = nil
  state.diff_win = nil
end

local function set_buffer_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function append_to_buffer(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function load_next_batch(offset)
  if not vim.api.nvim_buf_is_valid(state.log_buf) then
    kill_job()
    return
  end

  local cmd = {
    'git', 'log',
    '-L' .. state.start_line .. ',' .. state.end_line .. ':' .. state.file,
    '--format=%h %ad %s', '--date=format:%Y-%m-%d %H:%M:%S', '--no-patch',
    '-n', tostring(batch_size),
    '--skip', tostring(offset),
  }

  state.job = vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        if offset == 0 then
          set_buffer_lines(state.log_buf, { '-- No commits found --' })
        end
        stop_spinner()
        update_log_statusline(false)
        state.job = nil
        return
      end

      local stdout = result.stdout or ''
      if stdout == '' then
        if offset == 0 then
          set_buffer_lines(state.log_buf, { '-- No commits found --' })
        end
        stop_spinner()
        update_log_statusline(false)
        state.job = nil
        return
      end

      local lines = vim.split(stdout, '\n', { trimempty = true })
      if #lines == 0 then
        stop_spinner()
        update_log_statusline(false)
        state.job = nil
        return
      end

      state.commit_count = state.commit_count + #lines

      if offset == 0 then
        set_buffer_lines(state.log_buf, lines)
        highlight_commit_lines(state.log_buf, 0, lines)
      else
        local line_count = vim.api.nvim_buf_line_count(state.log_buf)
        append_to_buffer(state.log_buf, lines)
        highlight_commit_lines(state.log_buf, line_count, lines)
      end

      if #lines >= batch_size then
        load_next_batch(offset + batch_size)
      else
        stop_spinner()
        update_log_statusline(false)
        state.job = nil
      end
    end)
  end)
end

local function show_commit_diff()
  local line = vim.api.nvim_get_current_line()
  local commit, message = line:match('^(%x+)%s+[%d%-]+%s+[%d:]+%s+(.*)$')
  if not commit then
    commit = line:match('^(%x+)')
  end
  if not commit then
    vim.notify('No commit hash found on this line', vim.log.levels.WARN)
    return
  end

  if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
    vim.api.nvim_win_close(state.diff_win, true)
  end

  local cmd = {
    'git', 'log',
    '-L' .. state.start_line .. ',' .. state.end_line .. ':' .. state.file,
    '-1', commit,
    '--no-prefix',
  }

  state.diff_job = vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      state.diff_job = nil
      if not vim.api.nvim_win_is_valid(state.log_win) then
        return
      end
      if result.code ~= 0 then
        vim.notify('Failed to get diff: ' .. (result.stderr or ''), vim.log.levels.ERROR)
        return
      end

      local lines = vim.split(result.stdout or '', '\n')

      -- 找到 diff 内容开始的行号
      local diff_start = 1
      for i, l in ipairs(lines) do
        if l:match('^diff ') or l:match('^@@') then
          diff_start = i
          break
        end
      end

      state.diff_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[state.diff_buf].buftype = 'nofile'
      vim.bo[state.diff_buf].bufhidden = 'wipe'
      vim.bo[state.diff_buf].swapfile = false
      vim.bo[state.diff_buf].filetype = 'git'

      vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, lines)
      vim.bo[state.diff_buf].modifiable = false

      vim.api.nvim_set_current_win(state.log_win)
      vim.cmd('vsplit')
      state.diff_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(state.diff_win, state.diff_buf)

      -- 跳到 diff 内容开始处
      vim.api.nvim_win_set_cursor(state.diff_win, { diff_start, 0 })

      -- 设置 diff 窗口 statusline
      local short_msg = message and message:sub(1, 50) or ''
      if message and #message > 50 then
        short_msg = short_msg .. '...'
      end
      vim.wo[state.diff_win].statusline = string.format(
        ' %%#Function#Diff%%* %%#Number#%s%%* %%#Comment#%s%%*',
        commit, short_msg
      )

      vim.keymap.set('n', 'q', function()
        if vim.api.nvim_win_is_valid(state.diff_win) then
          vim.api.nvim_win_close(state.diff_win, true)
        end
      end, { buffer = state.diff_buf, nowait = true })
    end)
  end)
end

local function setup_log_buffer_keymaps(buf)
  local opts = { buffer = buf, nowait = true }

  vim.keymap.set('n', '<CR>', show_commit_diff, opts)

  vim.keymap.set('n', 'q', function()
    kill_job()
    if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
      vim.api.nvim_win_close(state.diff_win, true)
    end
    if state.log_win and vim.api.nvim_win_is_valid(state.log_win) then
      vim.api.nvim_win_close(state.log_win, true)
    end
  end, opts)
end

local function is_in_git_repo(file)
  local dir = vim.fn.fnamemodify(file, ':h')
  local result = vim.system({ 'git', '-C', dir, 'rev-parse', '--is-inside-work-tree' }, { text = true }):wait()
  return result.code == 0
end

function M.show()
  local start_line = vim.fn.getpos('v')[2]
  local end_line = vim.api.nvim_win_get_cursor(0)[1]
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local file = vim.fn.expand('%:p')
  if file == '' then
    vim.notify('No file', vim.log.levels.WARN)
    return
  end

  if not is_in_git_repo(file) then
    vim.notify('Not in a git repository', vim.log.levels.WARN)
    return
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)

  kill_job()
  if state.log_win and vim.api.nvim_win_is_valid(state.log_win) then
    vim.api.nvim_win_close(state.log_win, true)
  end
  if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
    vim.api.nvim_win_close(state.diff_win, true)
  end

  state.file = file
  state.start_line = start_line
  state.end_line = end_line
  state.commit_count = 0

  state.log_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.log_buf].buftype = 'nofile'
  vim.bo[state.log_buf].bufhidden = 'wipe'
  vim.bo[state.log_buf].swapfile = false
  vim.bo[state.log_buf].filetype = 'git'

  vim.api.nvim_buf_set_lines(state.log_buf, 0, -1, false, { '-- Loading... --' })
  vim.bo[state.log_buf].modifiable = false

  local height = math.floor(vim.api.nvim_win_get_height(0) / 2)
  vim.cmd('botright split')
  state.log_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.log_win, state.log_buf)
  vim.api.nvim_win_set_height(state.log_win, height)

  start_spinner()
  setup_log_buffer_keymaps(state.log_buf)

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.log_buf,
    once = true,
    callback = function()
      cleanup_state()
    end,
  })

  load_next_batch(0)
end

return M
