local M = {}
local visual_core_api = require('lu5je0.core.visual')
local timestamp_modify_ns = vim.api.nvim_create_namespace('timestamp-modify')
local DATETIME_LAYOUT = '0000-00-00 00:00:00'
local DATETIME_WIDTH = #DATETIME_LAYOUT

local function get_timestamp()
  if vim.api.nvim_get_mode().mode == 'v' then
    return visual_core_api.get_visual_selection_as_string()
  else
    return vim.fn.expand('<cword>')
  end
end

local function parse(timestamp)
  if string.len(timestamp) > 10 then
    timestamp = tonumber(timestamp) / math.pow(10, string.len(timestamp) - 10)
    timestamp = tostring(timestamp)
  end
  return os.date('%Y-%m-%d %H:%M:%S', timestamp)
end

function M.show_in_date()
  print(parse(get_timestamp()))
end

local function open_float_editor(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  local default = opts.default or ''
  local width = opts.fixed_width or DATETIME_WIDTH
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

-- 将 'YYYY-MM-DD HH:MM:SS' 格式的字符串转换为 Unix 时间戳 (秒)
-- 如果格式无效，返回 nil
local function string_to_timestamp(datetime_str)
  -- 使用模式匹配来解析字符串
  local y, m, d, H, minute, S = datetime_str:match('^(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)$')

  if not y then
    vim.notify("无效的时间格式。请输入 'YYYY-MM-DD HH:MM:SS'。", vim.log.levels.ERROR)
    return nil
  end

  -- 创建一个 table 供 os.time() 使用
  local t = {
    year = tonumber(y),
    month = tonumber(m),
    day = tonumber(d),
    hour = tonumber(H),
    min = tonumber(minute),
    sec = tonumber(S),
  }

  -- os.time() 会根据本地时区将 table 转换为时间戳
  -- 在转换前进行有效性检查
  if t.month < 1 or t.month > 12 or t.day < 1 or t.day > 31 or t.hour < 0 or t.hour > 23 or t.min < 0 or t.min > 59 or t.sec < 0 or t.sec > 59 then
    vim.notify("时间值超出范围 (例如月份应为 1-12)。", vim.log.levels.ERROR)
    return nil
  end

  return os.time(t)
end

local function get_number_bounds_at(buf, row, col)
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''
  local idx = col + 1

  local function is_digit(ch)
    return ch ~= '' and ch:match('%d') ~= nil
  end

  if idx < 1 or idx > #line or not is_digit(line:sub(idx, idx)) then
    return nil
  end

  local start_idx = idx
  while start_idx > 1 and is_digit(line:sub(start_idx - 1, start_idx - 1)) do
    start_idx = start_idx - 1
  end

  local end_idx = idx
  while end_idx < #line and is_digit(line:sub(end_idx + 1, end_idx + 1)) do
    end_idx = end_idx + 1
  end

  return {
    start_col0 = start_idx - 1,
    end_col0 = end_idx,
    text = line:sub(start_idx, end_idx),
  }
end

local function replace_number_at_cursor_at(buf, row, col, new_text)
  local bounds = get_number_bounds_at(buf, row, col)
  if not bounds then
    return false
  end

  vim.api.nvim_buf_set_text(buf, row - 1, bounds.start_col0, row - 1, bounds.end_col0, { new_text })
  return true
end

-- 主函数，用于转换和编辑时间戳
M.modify_timestamp = function()
  -- 1. 获取光标下的单词 (cword)
  local cword = vim.fn.expand('<cword>')

  if not cword or not cword:match('^%d+$') then
    vim.notify("光标下不是一个有效的时间戳数字。", vim.log.levels.WARN)
    return
  end

  -- 让 . 可以重复打开该命令，即使本次未确认
  pcall(vim.cmd, [[silent! call repeat#set("\<Plug>(TimestampModify)", 1)]])

  local original_ts = tonumber(cword)
  if not original_ts then return end

  -- 2. 判断是秒还是毫秒 (一个简单的启发式方法)
  -- 当前的秒级时间戳是 10 位，毫秒是 13 位。以 11 位作为分界线很安全。
  local is_millisecond = #cword > 10
  local ts_in_seconds = is_millisecond and (original_ts / 1000) or original_ts

  -- 3. 格式化为人类可读的时间字符串
  local display_format = '%Y-%m-%d %H:%M:%S'
  local default_datetime_str = os.date(display_format, ts_in_seconds)
  local origin_win = vim.api.nvim_get_current_win()
  local origin_buf = vim.api.nvim_get_current_buf()
  local origin_pos = vim.api.nvim_win_get_cursor(origin_win)
  local number_bounds = get_number_bounds_at(origin_buf, origin_pos[1], origin_pos[2])

  if not number_bounds then
    vim.notify("未在光标位置找到可修改的时间戳。", vim.log.levels.WARN)
    return
  end

  local prev_conceallevel = vim.wo[origin_win].conceallevel
  vim.wo[origin_win].conceallevel = 2
  local extmark_id = vim.api.nvim_buf_set_extmark(origin_buf, timestamp_modify_ns, origin_pos[1] - 1, number_bounds.start_col0, {
    end_col = number_bounds.end_col0,
    hl_group = 'Search',
    virt_text_pos = 'inline',
    virt_text = { { string.rep(' ', DATETIME_WIDTH), 'Search' } },
    conceal = '',
    priority = 200,
  })

  open_float_editor({
    default = default_datetime_str,
    fixed_width = DATETIME_WIDTH,
    anchor = {
      win = origin_win,
      row = origin_pos[1] - 1,
      col = number_bounds.start_col0,
    },
    on_close = function()
      if vim.api.nvim_win_is_valid(origin_win) then
        vim.wo[origin_win].conceallevel = prev_conceallevel
      end
      if vim.api.nvim_buf_is_valid(origin_buf) then
        pcall(vim.api.nvim_buf_del_extmark, origin_buf, timestamp_modify_ns, extmark_id)
      end
    end,
    on_submit = function(input)
      if not input or input == '' then
        return
      end

      -- 5. 将用户修改后的字符串转换回时间戳
      local new_ts_in_seconds = string_to_timestamp(input)
      if not new_ts_in_seconds then
        return
      end

      -- 6. 根据原始格式（秒或毫秒）生成新的时间戳字符串
      local final_ts_str
      if is_millisecond then
        final_ts_str = tostring(new_ts_in_seconds * 1000)
      else
        final_ts_str = tostring(new_ts_in_seconds)
      end

      -- 7. 替换光标所在的数字
      if not vim.api.nvim_buf_is_valid(origin_buf) then
        vim.notify("替换失败！原缓冲区无效。", vim.log.levels.ERROR)
        return
      end

      local ok = replace_number_at_cursor_at(origin_buf, origin_pos[1], origin_pos[2], final_ts_str)
      if ok then
        vim.print(string.format("，时间戳已更新为: %s", final_ts_str))
      else
        vim.notify("替换失败！未在光标位置找到原始时间戳。", vim.log.levels.ERROR)
      end
    end,
  })
end

return M
