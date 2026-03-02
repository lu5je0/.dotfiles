local utils = require('lu5je0.misc.timestamp.utils')

local M = {}
local timestamp_modify_ns = vim.api.nvim_create_namespace('timestamp-modify')

local function open_float_editor(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  local default = opts.default or ''
  local width = opts.fixed_width or utils.DATETIME_WIDTH
  local height = 1

  local win_opts = {
    width = width,
    height = height,
    style = 'minimal',
    border = 'none',
    zindex = 50,
  }

  if opts.anchor and vim.api.nvim_win_is_valid(opts.anchor.win) then
    -- Overlay exactly at target text position.
    win_opts.relative = 'win'
    win_opts.win = opts.anchor.win
    win_opts.bufpos = { opts.anchor.row, opts.anchor.col }
    win_opts.row = 0
    win_opts.col = 0
  else
    local win_height = vim.api.nvim_win_get_height(0)
    local cursor_row = vim.fn.winline()
    win_opts.relative = 'cursor'
    win_opts.row = (win_height - cursor_row < 2) and -1 or 1
    win_opts.col = 0
  end

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
  vim.api.nvim_set_option_value('wrap', false, { win = win })
  vim.api.nvim_set_option_value('winhighlight', 'NormalFloat:Search', { win = win })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })
  vim.api.nvim_buf_add_highlight(buf, -1, 'Search', 0, 0, -1)

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      vim.cmd('normal! 0')
    end
  end)

  local function close(commit)
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    local value = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ''
    vim.api.nvim_win_close(win, true)

    if opts.on_close then
      opts.on_close(commit, value)
    end

    if commit and opts.on_submit then
      opts.on_submit(value)
    end
  end

  local map_opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set('n', '<cr>', function()
    close(true)
  end, map_opts)
  vim.keymap.set('n', '<esc>', function()
    close(false)
  end, map_opts)
  vim.keymap.set('n', 'q', function()
    close(false)
  end, map_opts)

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = function()
      close(false)
    end,
  })
end

function M.modify_timestamp()
  local cword = vim.fn.expand('<cword>')

  if not cword or not cword:match('^%d+$') then
    vim.notify("光标下不是一个有效的时间戳数字。", vim.log.levels.WARN)
    return
  end

  pcall(vim.cmd, [[silent! call repeat#set("\<Plug>(TimestampModify)", 1)]])

  local original_ts = tonumber(cword)
  if not original_ts then
    return
  end

  local is_millisecond = #cword == 13
  local ts_in_seconds = is_millisecond and math.floor(original_ts / 1000) or original_ts

  local display_format = '%Y-%m-%d %H:%M:%S'
  local default_datetime_str = os.date(display_format, ts_in_seconds)
  if is_millisecond then
    default_datetime_str = string.format('%s.%03d', default_datetime_str, original_ts % 1000)
  end
  local editor_width = is_millisecond and utils.DATETIME_MILLI_WIDTH or utils.DATETIME_WIDTH
  local origin_win = vim.api.nvim_get_current_win()
  local origin_buf = vim.api.nvim_get_current_buf()
  local origin_pos = vim.api.nvim_win_get_cursor(origin_win)
  local number_bounds = utils.get_number_bounds_at(origin_buf, origin_pos[1], origin_pos[2])

  if not number_bounds then
    vim.notify("未在光标位置找到可修改的时间戳。", vim.log.levels.WARN)
    return
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(origin_buf, timestamp_modify_ns, origin_pos[1] - 1, number_bounds.start_col0, {
    end_col = number_bounds.end_col0,
    hl_group = 'Search',
    priority = 200,
  })

  local padding_extmark_id = nil
  local number_width = number_bounds.end_col0 - number_bounds.start_col0
  local pad_width = math.max(0, editor_width - number_width)
  if pad_width > 0 then
    padding_extmark_id = vim.api.nvim_buf_set_extmark(origin_buf, timestamp_modify_ns, origin_pos[1] - 1, number_bounds.end_col0, {
      virt_text_pos = 'inline',
      virt_text = { { string.rep(' ', pad_width), 'Search' } },
      priority = 199,
    })
  end

  open_float_editor({
    default = default_datetime_str,
    fixed_width = editor_width,
    anchor = {
      win = origin_win,
      row = origin_pos[1] - 1,
      col = number_bounds.start_col0,
    },
    on_close = function()
      if vim.api.nvim_buf_is_valid(origin_buf) then
        pcall(vim.api.nvim_buf_del_extmark, origin_buf, timestamp_modify_ns, extmark_id)
        if padding_extmark_id then
          pcall(vim.api.nvim_buf_del_extmark, origin_buf, timestamp_modify_ns, padding_extmark_id)
        end
      end
    end,
    on_submit = function(input)
      if not input or input == '' then
        return
      end

      local new_ts_in_seconds, new_ts_millis = utils.string_to_timestamp(input)
      if not new_ts_in_seconds then
        return
      end

      local final_ts_str
      if is_millisecond then
        final_ts_str = tostring(new_ts_in_seconds * 1000 + new_ts_millis)
      else
        final_ts_str = tostring(new_ts_in_seconds)
      end

      if not vim.api.nvim_buf_is_valid(origin_buf) then
        vim.notify("替换失败！原缓冲区无效。", vim.log.levels.ERROR)
        return
      end

      local ok = utils.replace_number_at_cursor_at(origin_buf, origin_pos[1], origin_pos[2], final_ts_str)
      if ok then
        vim.print(string.format("，时间戳已更新为: %s", final_ts_str))
      else
        vim.notify("替换失败！未在光标位置找到原始时间戳。", vim.log.levels.ERROR)
      end
    end,
  })
end

return M
