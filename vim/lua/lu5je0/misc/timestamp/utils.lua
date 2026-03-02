local M = {}

M.DATETIME_LAYOUT = '0000-00-00 00:00:00'
M.DATETIME_WIDTH = #M.DATETIME_LAYOUT
M.DATETIME_MILLI_LAYOUT = '0000-00-00 00:00:00.000'
M.DATETIME_MILLI_WIDTH = #M.DATETIME_MILLI_LAYOUT

function M.parse(timestamp)
  if string.len(timestamp) > 10 then
    timestamp = tonumber(timestamp) / math.pow(10, string.len(timestamp) - 10)
    timestamp = tostring(timestamp)
  end
  return os.date('%Y-%m-%d %H:%M:%S', timestamp)
end

function M.format_timestamp_like(raw)
  if not raw or not raw:match('^%d+$') then
    return nil
  end

  local len = #raw
  if len ~= 10 and len ~= 13 then
    return nil
  end

  local ts = tonumber(raw)
  if not ts then
    return nil
  end
  if len == 13 then
    ts = math.floor(ts / 1000)
  end

  -- Keep the match conservative to avoid random long numbers/IDs.
  if ts < 946684800 or ts > 4102444800 then
    return nil
  end

  local ok, formatted = pcall(os.date, '%Y-%m-%d %H:%M:%S', ts)
  if not ok then
    return nil
  end
  return formatted
end

function M.string_to_timestamp(datetime_str)
  local y, m, d, H, minute, S, milli = datetime_str:match('^(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)%.?(%d*)$')

  if not y then
    vim.notify("无效的时间格式。请输入 'YYYY-MM-DD HH:MM:SS' 或 'YYYY-MM-DD HH:MM:SS.SSS'。", vim.log.levels.ERROR)
    return nil
  end

  milli = milli or ''
  if #milli > 3 then
    vim.notify("毫秒值超出范围（最多 3 位）。", vim.log.levels.ERROR)
    return nil
  end

  local milli_num = 0
  if #milli > 0 then
    milli_num = tonumber(milli) * math.pow(10, 3 - #milli)
  end

  local t = {
    year = tonumber(y),
    month = tonumber(m),
    day = tonumber(d),
    hour = tonumber(H),
    min = tonumber(minute),
    sec = tonumber(S),
  }

  if t.month < 1 or t.month > 12 or t.day < 1 or t.day > 31 or t.hour < 0 or t.hour > 23 or t.min < 0 or t.min > 59 or t.sec < 0 or t.sec > 59 then
    vim.notify("时间值超出范围 (例如月份应为 1-12)。", vim.log.levels.ERROR)
    return nil
  end

  return os.time(t), milli_num
end

function M.get_number_bounds_at(buf, row, col)
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

function M.replace_number_at_cursor_at(buf, row, col, new_text)
  local bounds = M.get_number_bounds_at(buf, row, col)
  if not bounds then
    return false
  end

  vim.api.nvim_buf_set_text(buf, row - 1, bounds.start_col0, row - 1, bounds.end_col0, { new_text })
  return true
end

return M
