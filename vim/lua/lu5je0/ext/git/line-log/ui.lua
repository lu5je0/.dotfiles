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

M.close_help = close_help

local function show_help()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    close_help()
    return
  end

  local help_lines = {
    'Line Log Keymaps',
    '',
    '  j/k     Move commit (auto show diff)',
    '  v/V     Visual select (auto show aggregated diff)',
    '  d       Toggle diff mode: single / dual',
    '  D       Toggle changes-only (single mode)',
    '  ?       Show this help',
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
    local total = state.tracker and #state.tracker.revisions or 0
    local current = state.tracker and state.tracker.current_idx or 0
    local status = total > 0 and string.format('%d/%d', current, total) or '...'
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

local function append_display_line(state, line, item)
  if not vim.api.nvim_buf_is_valid(state.log_buf) then
    return
  end
  vim.bo[state.log_buf].modifiable = true
  if state.commit_count == 0 then
    vim.api.nvim_buf_set_lines(state.log_buf, 0, -1, false, { line })
  else
    vim.api.nvim_buf_set_lines(state.log_buf, -1, -1, false, { line })
  end
  state.display_items[#state.display_items + 1] = item
  state.commit_count = #state.display_items
  vim.bo[state.log_buf].modifiable = false
  M.update_log_statusline(state, true)
end

function M.append_commit_line(state, rev, rev_idx)
  local line = string.format('%s %s %s %s', rev.hash, rev.date, rev.author, rev.message)
  append_display_line(state, line, {
    type = 'revision',
    rev_idx = rev_idx,
  })
  M.highlight_commit_lines(state.log_buf, state.commit_count - 1, { line }, { rev })
end

function M.append_local_change_line(state)
  local line = 'local change'
  append_display_line(state, line, {
    type = 'local_change',
  })
  vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Special', state.commit_count - 1, 0, -1)
end

local function get_item_at_line(state, line_nr)
  return state.display_items[line_nr]
end

local function get_display_selection(state, from_line, to_line)
  local min_idx, max_idx = nil, nil
  for line_nr = from_line, to_line do
    if get_item_at_line(state, line_nr) then
      if not min_idx or line_nr < min_idx then
        min_idx = line_nr
      end
      if not max_idx or line_nr > max_idx then
        max_idx = line_nr
      end
    end
  end
  if not min_idx then
    return nil
  end
  return {
    from_display_idx = min_idx,
    to_display_idx = max_idx,
    newest_item = state.display_items[min_idx],
    oldest_item = state.display_items[max_idx],
  }
end

local function get_new_side(state, item)
  local tracker = state.tracker
  if item.type == 'local_change' then
    return tracker and tracker.blocks[0] or nil, state.rel_file
  end

  local rev = tracker and tracker.revisions[item.rev_idx] or nil
  return tracker and tracker.blocks[item.rev_idx] or nil, rev and rev.file or state.rel_file
end

local function get_old_side(state, item)
  local tracker = state.tracker
  if item.type == 'local_change' then
    return tracker and tracker.local_change_block or nil, state.rel_file, tracker and tracker.revisions[1] or nil
  end

  local parent_idx = item.rev_idx + 1
  local rev = tracker and tracker.revisions[item.rev_idx] or nil
  local parent_rev = tracker and parent_idx <= #tracker.revisions and tracker.revisions[parent_idx] or nil
  local old_file = parent_rev and parent_rev.file or rev.file
  return tracker and tracker.blocks[parent_idx] or nil, old_file, parent_rev
end

local function get_item_summary(state, item)
  if item.type == 'local_change' then
    return {
      short = 'local change',
      detail = 'working tree',
    }
  end

  local tracker = state.tracker
  local rev = tracker and tracker.revisions[item.rev_idx] or nil
  if not rev then
    return {
      short = '?',
      detail = 'missing revision',
    }
  end
  local short_msg = rev.message:sub(1, 50)
  if #rev.message > 50 then
    short_msg = short_msg .. '...'
  end
  return {
    short = rev.hash,
    detail = short_msg,
  }
end

local function get_range_summary(state, newest_item, oldest_item)
  local newest = get_item_summary(state, newest_item)
  local oldest = get_item_summary(state, oldest_item)
  return newest.short, oldest.short
end

local function is_tracked_diff_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  return vim.w[win].git_line_log_diff == true
end

local function mark_diff_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.w[win].git_line_log_diff = true
  end
end

local function reset_diff_state(state)
  state.diff_win = nil
  state.diff_buf = nil
  state.diff_win2 = nil
  state.diff_buf2 = nil
end

local function close_diff_windows(state)
  state.closing_diff_windows = true
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    if is_tracked_diff_window(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  for _, win in ipairs({ state.diff_win2, state.diff_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  reset_diff_state(state)
  state.closing_diff_windows = false
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

  local selection = get_display_selection(state, from_line, to_line)
  if not selection then
    return
  end

  local new_block, new_file = get_new_side(state, selection.newest_item)
  local old_block, old_file, old_rev = get_old_side(state, selection.oldest_item)

  if state.diff_mode == 'dual' then
    M.show_dual_diff(state, old_block, new_block, old_file, new_file, selection, old_rev)
  else
    M.show_single_diff(state, old_block, new_block, old_file, new_file, selection)
  end
end

function M.show_single_diff(state, old_block, new_block, old_file, new_file, selection)
  local diff_opts = state.diff_changes_only and { ctxlen = 3 } or nil
  local lines = Block.generate_diff(old_block, new_block, old_file, new_file, diff_opts)

  local was_dual = state.diff_win2 and vim.api.nvim_win_is_valid(state.diff_win2)

  -- Switching from dual mode back to single mode is simpler if we rebuild the
  -- diff window from scratch instead of trying to reuse the left diff pane.
  if was_dual then
    close_diff_windows(state)
  end

  local reuse_win = state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) and not state.diff_win2

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
    mark_diff_window(state.diff_win)
    vim.api.nvim_set_current_win(state.log_win)

  end

  -- Statusline: single commit or range
  if selection.from_display_idx == selection.to_display_idx then
    local summary = get_item_summary(state, selection.newest_item)
    vim.wo[state.diff_win].statusline = string.format(
      ' %%#Function#Diff%%* %%#Number#%s%%* %%#Comment#%s%%*',
      summary.short,
      summary.detail
    )
  else
    local newest_label, oldest_label = get_range_summary(state, selection.newest_item, selection.oldest_item)
    local count = selection.to_display_idx - selection.from_display_idx + 1
    vim.wo[state.diff_win].statusline = string.format(
      ' %%#Function#Diff%%* %%#Number#%s..%s%%* %%#Comment#(%d commits)%%*',
      newest_label,
      oldest_label,
      count
    )
  end
end

function M.show_dual_diff(state, old_block, new_block, old_file, new_file, selection, old_rev)
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
    close_diff_windows(state)

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
    mark_diff_window(state.diff_win)
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
    mark_diff_window(state.diff_win2)
    vim.wo[state.diff_win2].diff = true
    vim.wo[state.diff_win2].scrollbind = true
    vim.wo[state.diff_win2].wrap = false
    vim.wo[state.diff_win2].statuscolumn = '%=%{v:virtnum==0?v:lnum+b:line_offset:""} '

    -- Auto-close the other diff window when one is closed
    local closing = false
    for _, buf_pair in ipairs({ { state.diff_buf, state.diff_win2 }, { state.diff_buf2, state.diff_win } }) do
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf_pair[1],
        once = true,
        callback = function()
          if state.closing_diff_windows then
            return
          end
          if closing then
            return
          end
          closing = true
          close_diff_windows(state)
        end,
      })
    end

    vim.api.nvim_set_current_win(state.log_win)
  end

  -- Fold unchanged regions when changes-only mode is active
  for _, win in ipairs({ state.diff_win, state.diff_win2 }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.wo[win].foldmethod = 'diff'
      vim.wo[win].foldlevel = 0
      vim.wo[win].foldenable = state.diff_changes_only
    end
  end

  -- Update statuslines
  if selection.from_display_idx == selection.to_display_idx then
    local new_summary = get_item_summary(state, selection.newest_item)
    if old_rev then
      local old_msg = old_rev.message:sub(1, 30)
      if #old_rev.message > 30 then
        old_msg = old_msg .. '...'
      end
      vim.wo[state.diff_win].statusline = string.format('%%#Comment#%s %s%%*', old_rev.hash, old_msg)
    else
      vim.wo[state.diff_win].statusline = '%#Comment#(initial)%*'
    end
    vim.wo[state.diff_win2].statusline = string.format('%%#Number#%s%%* %%#Comment#%s%%*', new_summary.short, new_summary.detail)
  else
    local newest_label, oldest_label = get_range_summary(state, selection.newest_item, selection.oldest_item)
    local count = selection.to_display_idx - selection.from_display_idx + 1
    vim.wo[state.diff_win].statusline = string.format('%%#Comment#before %s%%*', oldest_label)
    vim.wo[state.diff_win2].statusline = string.format('%%#Number#%s..%s%%* %%#Comment#(%d commits)%%*', newest_label, oldest_label, count)
  end
end

function M.setup_log_buffer_keymaps(state, toggle_diff_mode, toggle_diff_changes_only)
  local buf = state.log_buf
  local opts = { buffer = buf, nowait = true }
  local diff_preview_timer = vim.uv.new_timer()

  local function stop_diff_preview_timer()
    if diff_preview_timer then
      diff_preview_timer:stop()
      diff_preview_timer:close()
      diff_preview_timer = nil
    end
  end

  local function show_commit_diff_debounced()
    local session_log_buf = state.log_buf
    if not diff_preview_timer then
      return
    end
    if not state.log_buf or not vim.api.nvim_buf_is_valid(state.log_buf) then
      return
    end
    diff_preview_timer:stop()
    diff_preview_timer:start(80, 0, vim.schedule_wrap(function()
      if not diff_preview_timer then
        return
      end
      if not state.log_buf or state.log_buf ~= session_log_buf or not vim.api.nvim_buf_is_valid(state.log_buf) then
        return
      end
      if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
        return
      end
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
    end))
  end

  -- Auto-update diff on cursor move
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = function()
      show_commit_diff_debounced()
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = stop_diff_preview_timer,
  })

  vim.keymap.set('n', 'd', function()
    toggle_diff_mode()
    M.show_commit_diff(state)
  end, opts)

  vim.keymap.set('n', 'D', function()
    toggle_diff_changes_only()
    M.show_commit_diff(state)
  end, opts)

  vim.keymap.set('n', '?', show_help, opts)
  vim.keymap.set('n', '<cr>', '<nop>', opts)
end

return M
