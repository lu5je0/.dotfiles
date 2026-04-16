local Block = require('lu5je0.ext.git.line-log.block')

local M = {}

local ns_id = vim.api.nvim_create_namespace('git_line_log')

local help_win = nil
local help_buf = nil

local function close_help()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    vim.api.nvim_win_close(help_win, true)
    help_win = nil
    help_buf = nil
  end
end

local function show_help()
  -- Close existing help if open
  close_help()

  local help_lines = {
    'Line Log Keymaps',
    '',
    '  j/k     Move commit (auto show diff)',
    '  v/V     Visual select (auto show aggregated diff)',
    '  d       Toggle diff mode: single / dual',
    '  ?       Show this help',
    '  q/<Esc> Close',
    '',
    'Diff modes:',
    '  single: Unified diff format',
    '  dual:   Side-by-side vimdiff style',
  }

  help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].buftype = 'nofile'
  vim.bo[help_buf].bufhidden = 'wipe'
  vim.bo[help_buf].swapfile = false
  vim.bo[help_buf].filetype = 'help'

  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)
  vim.bo[help_buf].modifiable = false

  -- Calculate position relative to log_win
  local log_win = vim.api.nvim_get_current_win()
  local log_pos = vim.api.nvim_win_get_position(log_win)
  local log_height = vim.api.nvim_win_get_height(log_win)
  local log_width = vim.api.nvim_win_get_width(log_win)

  local win_width = 40
  local win_height = #help_lines + 2
  local col = log_pos[2] + math.floor((log_width - win_width) / 2)
  local row = log_pos[1] + math.floor((log_height - win_height) / 2)

  help_win = vim.api.nvim_open_win(help_buf, false, {
    relative = 'editor',
    row = row,
    col = col,
    width = win_width,
    height = win_height,
    style = 'minimal',
    border = 'rounded',
    title = ' Help ',
    title_pos = 'center',
    zindex = 100,
  })
  vim.wo[help_win].winhighlight = 'Normal:Normal,FloatBorder:Special'

  -- Close help on any key press or buffer leave
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave', 'InsertEnter' }, {
    buffer = help_buf,
    once = true,
    callback = close_help,
  })

  -- Close help after a timeout or on key press
  vim.keymap.set('n', '?', close_help, { buffer = help_buf, nowait = true })
end

function M.update_log_statusline(state, loading)
  if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
    return
  end
  local filename = vim.fn.fnamemodify(state.file, ':t')
  local line_range = state.start_line == state.end_line and tostring(state.start_line)
    or string.format('%d-%d', state.start_line, state.end_line)

  if loading then
    local total = #state.revisions
    local status = total > 0 and string.format('%d/%d', state.current_idx, total) or '...'
    vim.wo[state.log_win].statusline = string.format(' %%#Function#Log%%* L%%#Number#%s%%* [%%#Special#%s%%*] %%#Comment#%s%%*', line_range, status, filename)
  else
    vim.wo[state.log_win].statusline = string.format(' %%#Function#Log%%* L%%#Number#%s%%* %%#Comment#%s%%*', line_range, filename)
  end
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

  -- new_block = block at newest selected commit (+ side)
  -- old_block = block before oldest selected commit (- side)
  local new_block = state.blocks[min_rev_idx]
  local old_block = state.blocks[max_rev_idx + 1]

  local new_file = state.revisions[min_rev_idx].file
  local old_rev_idx = max_rev_idx + 1
  local old_file = (old_rev_idx <= #state.revisions) and state.revisions[old_rev_idx].file or new_file

  if state.diff_mode == 'dual' then
    M.show_dual_diff(state, old_block, new_block, old_file, new_file, min_rev_idx, max_rev_idx, from_line, to_line)
  else
    M.show_single_diff(state, old_block, new_block, old_file, new_file, min_rev_idx, max_rev_idx, from_line, to_line)
  end
end

function M.show_single_diff(state, old_block, new_block, old_file, new_file, min_rev_idx, max_rev_idx, from_line, to_line)
  local lines = Block.generate_diff(old_block, new_block, old_file, new_file)

  -- Close diff_win2 if exists
  if state.diff_win2 and vim.api.nvim_win_is_valid(state.diff_win2) then
    vim.api.nvim_win_close(state.diff_win2, true)
    state.diff_win2 = nil
    state.diff_buf2 = nil
  end

  local reuse_win = state.diff_win and vim.api.nvim_win_is_valid(state.diff_win)

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

function M.show_dual_diff(state, old_block, new_block, old_file, new_file, min_rev_idx, max_rev_idx, from_line, to_line)
  local old_lines = (old_block and not old_block:is_empty()) and old_block:get_content() or {}
  local new_lines = (new_block and not new_block:is_empty()) and new_block:get_content() or {}

  local old_offset = (old_block and not old_block:is_empty()) and (old_block.start_line - 1) or 0
  local new_offset = (new_block and not new_block:is_empty()) and (new_block.start_line - 1) or 0

  -- Get filetype from source buffer for syntax highlighting
  local ft = state.source_buf and vim.api.nvim_buf_is_valid(state.source_buf)
    and vim.bo[state.source_buf].filetype or nil

  local reuse_win = state.diff_win and vim.api.nvim_win_is_valid(state.diff_win)
    and state.diff_win2 and vim.api.nvim_win_is_valid(state.diff_win2)

  if reuse_win then
    -- Update old diff
    vim.bo[state.diff_buf].modifiable = true
    if ft then
      vim.bo[state.diff_buf].filetype = ft
    end
    vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, old_lines)
    vim.bo[state.diff_buf].modifiable = false
    vim.b[state.diff_buf].line_offset = old_offset

    -- Update new diff
    vim.bo[state.diff_buf2].modifiable = true
    if ft then
      vim.bo[state.diff_buf2].filetype = ft
    end
    vim.api.nvim_buf_set_lines(state.diff_buf2, 0, -1, false, new_lines)
    vim.bo[state.diff_buf2].modifiable = false
    vim.b[state.diff_buf2].line_offset = new_offset

    -- Sync scroll
    vim.api.nvim_win_call(state.diff_win, function()
      vim.cmd('diffupdate')
    end)
  else
    -- Close existing single diff win
    if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
      vim.api.nvim_win_close(state.diff_win, true)
      state.diff_win = nil
      state.diff_buf = nil
    end

    -- Create old diff buffer and window
    state.diff_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.diff_buf].buftype = 'nofile'
    vim.bo[state.diff_buf].bufhidden = 'wipe'
    vim.bo[state.diff_buf].swapfile = false
    if ft then
      vim.bo[state.diff_buf].filetype = ft
    end
    vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, old_lines)
    vim.bo[state.diff_buf].modifiable = false
    vim.b[state.diff_buf].line_offset = old_offset

    vim.api.nvim_set_current_win(state.log_win)
    vim.cmd('vsplit')
    state.diff_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.diff_win, state.diff_buf)
    vim.wo[state.diff_win].diff = true
    vim.wo[state.diff_win].scrollbind = true
    vim.wo[state.diff_win].wrap = false
    vim.wo[state.diff_win].statuscolumn = '%=%{v:virtnum==0?v:lnum+b:line_offset:""} '

    -- Create new diff buffer and window
    state.diff_buf2 = vim.api.nvim_create_buf(false, true)
    vim.bo[state.diff_buf2].buftype = 'nofile'
    vim.bo[state.diff_buf2].bufhidden = 'wipe'
    vim.bo[state.diff_buf2].swapfile = false
    if ft then
      vim.bo[state.diff_buf2].filetype = ft
    end
    vim.api.nvim_buf_set_lines(state.diff_buf2, 0, -1, false, new_lines)
    vim.bo[state.diff_buf2].modifiable = false
    vim.b[state.diff_buf2].line_offset = new_offset

    vim.cmd('vsplit')
    state.diff_win2 = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.diff_win2, state.diff_buf2)
    vim.wo[state.diff_win2].diff = true
    vim.wo[state.diff_win2].scrollbind = true
    vim.wo[state.diff_win2].wrap = false
    vim.wo[state.diff_win2].statuscolumn = '%=%{v:virtnum==0?v:lnum+b:line_offset:""} '

    vim.api.nvim_set_current_win(state.log_win)
  end

  -- Update statuslines
  if from_line == to_line then
    local new_rev = state.revisions[min_rev_idx]
    local new_msg = new_rev.message:sub(1, 30)
    if #new_rev.message > 30 then
      new_msg = new_msg .. '...'
    end

    local parent_idx = max_rev_idx + 1
    local old_rev = parent_idx <= #state.revisions and state.revisions[parent_idx] or nil
    if old_rev then
      local old_msg = old_rev.message:sub(1, 30)
      if #old_rev.message > 30 then
        old_msg = old_msg .. '...'
      end
      vim.wo[state.diff_win].statusline = string.format('%%#Comment#%s %s%%*', old_rev.hash, old_msg)
    else
      vim.wo[state.diff_win].statusline = '%#Comment#(initial)%*'
    end
    vim.wo[state.diff_win2].statusline = string.format('%%#Number#%s%%* %%#Comment#%s%%*', new_rev.hash, new_msg)
  else
    local newest_hash = state.revisions[min_rev_idx].hash
    local oldest_hash = state.revisions[max_rev_idx].hash
    local count = to_line - from_line + 1
    vim.wo[state.diff_win].statusline = string.format('%%#Comment#before %s%%*', oldest_hash)
    vim.wo[state.diff_win2].statusline = string.format('%%#Number#%s..%s%%* %%#Comment#(%d commits)%%*', newest_hash, oldest_hash, count)
  end
end

function M.setup_log_buffer_keymaps(state, on_quit, toggle_diff_mode)
  local buf = state.log_buf
  local opts = { buffer = buf, nowait = true }

  -- Auto-update diff on cursor move
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = function()
      if state.commit_count == 0 then
        return
      end
      local mode = vim.fn.mode()
      if mode == 'n' then
        M.show_commit_diff(state)
      elseif mode == 'v' or mode == 'V' or mode == '\22' then -- v, V, Ctrl-V
        local vstart = vim.fn.getpos('v')[2]
        local vend = vim.api.nvim_win_get_cursor(state.log_win)[1]
        M.show_commit_diff(state, vstart, vend)
      end
    end,
  })

  vim.keymap.set('n', 'd', function()
    toggle_diff_mode()
    M.show_commit_diff(state)
  end, opts)

  vim.keymap.set('n', '?', show_help, opts)

  vim.keymap.set('n', 'q', function()
    on_quit()
    close_help()
    for _, win in ipairs({ state.diff_win2, state.diff_win, state.log_win }) do
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
  end, opts)

  vim.keymap.set('n', '<Esc>', function()
    on_quit()
    close_help()
    for _, win in ipairs({ state.diff_win2, state.diff_win, state.log_win }) do
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
  end, opts)
end

return M
