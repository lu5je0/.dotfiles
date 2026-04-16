local Block = require('lu5je0.ext.git.line-log.block')

local M = {}

local ns_id = vim.api.nvim_create_namespace('git_line_log')
local spinner = { '󰪞', '󰪟', '󰪠', '󰪡', '󰪢', '󰪣', '󰪤', '󰪥' }

function M.update_log_statusline(state, loading)
  if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
    return
  end
  local filename = vim.fn.fnamemodify(state.file, ':t')
  local line_range = state.start_line == state.end_line and tostring(state.start_line) or string.format('%d-%d', state.start_line, state.end_line)
  local status
  if loading then
    status = tostring(state.commit_count) .. ' ' .. spinner[state.spinner_idx]
  else
    status = tostring(state.commit_count)
  end
  vim.wo[state.log_win].statusline = string.format(' %%#Function#Log%%* L%%#Number#%s%%* [%%#Special#%s%%*] %%#Comment#%s%%*', line_range, status, filename)
end

function M.stop_spinner(state)
  if state.spinner_timer then
    vim.fn.timer_stop(state.spinner_timer)
    state.spinner_timer = nil
  end
end

function M.start_spinner(state)
  M.stop_spinner(state)
  state.spinner_idx = 1
  M.update_log_statusline(state, true)
  state.spinner_timer = vim.fn.timer_start(50, function()
    if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
      M.stop_spinner(state)
      return
    end
    state.spinner_idx = (state.spinner_idx % #spinner) + 1
    M.update_log_statusline(state, true)
  end, { ['repeat'] = -1 })
end

function M.highlight_commit_lines(buf, start_idx, lines, revs)
  for i, line in ipairs(lines) do
    local hash_end = line:find(' ')
    if hash_end then
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'Number', start_idx + i - 1, 0, hash_end - 1)
      local date_start = hash_end
      local date_end = hash_end + 19
      if #line >= date_end then
        vim.api.nvim_buf_add_highlight(buf, ns_id, 'Comment', start_idx + i - 1, date_start, date_end)
      end
      local rev = revs and revs[i]
      if rev and rev.author and #rev.author > 0 then
        local author_start = date_end + 1
        vim.api.nvim_buf_add_highlight(buf, ns_id, 'Special', start_idx + i - 1, author_start, author_start + #rev.author)
      end
    end
  end
end

function M.set_buffer_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.append_commit_line(state, rev)
  if not vim.api.nvim_buf_is_valid(state.log_buf) then
    return
  end
  local line = string.format('%s %s %s %s', rev.hash, rev.date, rev.author, rev.message)
  vim.bo[state.log_buf].modifiable = true
  if state.commit_count == 0 then
    vim.api.nvim_buf_set_lines(state.log_buf, 0, -1, false, { line })
  else
    vim.api.nvim_buf_set_lines(state.log_buf, -1, -1, false, { line })
  end
  state.commit_count = state.commit_count + 1
  M.highlight_commit_lines(state.log_buf, state.commit_count - 1, { line }, { rev })
  vim.bo[state.log_buf].modifiable = false
  M.update_log_statusline(state, true)
end

function M.show_commit_diff(state, from_line, to_line)
  if not from_line then
    from_line = vim.api.nvim_win_get_cursor(state.log_win)[1]
  end
  if not to_line then
    to_line = from_line
  end
  if from_line > to_line then
    from_line, to_line = to_line, from_line
  end

  -- Collect rev_idx for all selected lines
  local min_rev_idx, max_rev_idx = nil, nil
  for line_nr = from_line, to_line do
    local line = vim.api.nvim_buf_get_lines(state.log_buf, line_nr - 1, line_nr, false)[1]
    if line then
      local commit = line:match('^(%x+)')
      if commit then
        for i, rev in ipairs(state.revisions) do
          if rev.hash == commit then
            if not min_rev_idx or i < min_rev_idx then
              min_rev_idx = i
            end
            if not max_rev_idx or i > max_rev_idx then
              max_rev_idx = i
            end
            break
          end
        end
      end
    end
  end

  if not min_rev_idx then
    return
  end

  local reuse_win = state.diff_win and vim.api.nvim_win_is_valid(state.diff_win)

  -- new_block = block at newest selected commit (+ side)
  -- old_block = block before oldest selected commit (- side)
  local new_block = state.blocks[min_rev_idx]
  local old_block = state.blocks[max_rev_idx + 1]

  local new_file = state.revisions[min_rev_idx].file
  local old_rev_idx = max_rev_idx + 1
  local old_file = (old_rev_idx <= #state.revisions) and state.revisions[old_rev_idx].file or new_file

  local lines = Block.generate_diff(old_block, new_block, old_file, new_file)

  if reuse_win then
    vim.bo[state.diff_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, lines)
    vim.bo[state.diff_buf].modifiable = false
  else
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
    vim.api.nvim_set_current_win(state.log_win)

    vim.keymap.set('n', 'q', function()
      if vim.api.nvim_win_is_valid(state.diff_win) then
        vim.api.nvim_win_close(state.diff_win, true)
      end
    end, { buffer = state.diff_buf, nowait = true })
  end

  -- Statusline: single commit or range
  if from_line == to_line then
    local rev = state.revisions[min_rev_idx]
    local short_msg = rev and rev.message:sub(1, 50) or ''
    if rev and #rev.message > 50 then
      short_msg = short_msg .. '...'
    end
    vim.wo[state.diff_win].statusline = string.format(' %%#Function#Diff%%* %%#Number#%s%%* %%#Comment#%s%%*', rev.hash, short_msg)
  else
    local newest_hash = state.revisions[min_rev_idx].hash
    local oldest_hash = state.revisions[max_rev_idx].hash
    local count = to_line - from_line + 1
    vim.wo[state.diff_win].statusline = string.format(
      ' %%#Function#Diff%%* %%#Number#%s..%s%%* %%#Comment#(%d commits)%%*',
      newest_hash,
      oldest_hash,
      count
    )
  end
end

function M.setup_log_buffer_keymaps(state, on_quit)
  local buf = state.log_buf
  local opts = { buffer = buf, nowait = true }

  vim.keymap.set('n', '<CR>', function()
    M.show_commit_diff(state)
  end, opts)

  vim.keymap.set('x', '<CR>', function()
    local vstart = vim.fn.getpos('v')[2]
    local vend = vim.api.nvim_win_get_cursor(state.log_win)[1]
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    M.show_commit_diff(state, vstart, vend)
  end, opts)

  vim.keymap.set('n', 'J', function()
    local line_count = vim.api.nvim_buf_line_count(state.log_buf)
    local cursor_line = vim.api.nvim_win_get_cursor(state.log_win)[1]
    if cursor_line < line_count then
      vim.api.nvim_win_set_cursor(state.log_win, { cursor_line + 1, 0 })
      M.show_commit_diff(state)
    end
  end, opts)

  vim.keymap.set('n', 'K', function()
    local cursor_line = vim.api.nvim_win_get_cursor(state.log_win)[1]
    if cursor_line > 1 then
      vim.api.nvim_win_set_cursor(state.log_win, { cursor_line - 1, 0 })
      M.show_commit_diff(state)
    end
  end, opts)

  vim.keymap.set('n', 'q', function()
    on_quit()
    if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
      vim.api.nvim_win_close(state.diff_win, true)
    end
    if state.log_win and vim.api.nvim_win_is_valid(state.log_win) then
      vim.api.nvim_win_close(state.log_win, true)
    end
  end, opts)
end

return M
