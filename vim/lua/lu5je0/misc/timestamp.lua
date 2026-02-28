local M = {}
local visual_core_api = require('lu5je0.core.visual')

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
  local title = opts.title or 'Edit'
  local max_width = math.floor(vim.o.columns * 0.8)
  local width = math.min(math.max(24, #default + 6), max_width)
  local height = 1
  local win_height = vim.api.nvim_win_get_height(0)
  local cursor_row = vim.fn.winline()
  local row = 1
  if win_height - cursor_row < 2 then
    row = -1
  end
  local col = 0

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'center',
    zindex = 50,
  })

  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
  vim.api.nvim_set_option_value('wrap', false, { win = win })
  vim.api.nvim_set_option_value('winhighlight', 'NormalFloat:Normal,FloatBorder:Comment', { win = win })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })
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

local function replace_number_at_cursor_at(buf, row, col, new_text)
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''
  local idx = col + 1

  local function is_digit(ch)
    return ch ~= '' and ch:match('%d') ~= nil
  end

  if idx < 1 or idx > #line or not is_digit(line:sub(idx, idx)) then
    return false
  end

  local start_idx = idx
  while start_idx > 1 and is_digit(line:sub(start_idx - 1, start_idx - 1)) do
    start_idx = start_idx - 1
  end

  local end_idx = idx
  while end_idx < #line and is_digit(line:sub(end_idx + 1, end_idx + 1)) do
    end_idx = end_idx + 1
  end

  vim.api.nvim_buf_set_text(buf, row - 1, start_idx - 1, row - 1, end_idx, { new_text })
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

  open_float_editor({
    title = 'Timestamp',
    default = default_datetime_str,
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
