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

-- 主函数，用于转换和编辑时间戳
M.modify_timestamp = function()
  -- 1. 获取光标下的单词 (cword)
  local cword = vim.fn.expand('<cword>')

  if not cword or not cword:match('^%d+$') then
    vim.notify("光标下不是一个有效的时间戳数字。", vim.log.levels.WARN)
    return
  end

  local original_ts = tonumber(cword)
  if not original_ts then return end

  -- 2. 判断是秒还是毫秒 (一个简单的启发式方法)
  -- 当前的秒级时间戳是 10 位，毫秒是 13 位。以 11 位作为分界线很安全。
  local is_millisecond = #cword > 10
  local ts_in_seconds = is_millisecond and (original_ts / 1000) or original_ts

  -- 3. 格式化为人类可读的时间字符串
  local display_format = '%Y-%m-%d %H:%M:%S'
  local default_datetime_str = os.date(display_format, ts_in_seconds)

  -- 4. 使用 vim.ui.input 弹出可编辑的命令行输入框
  vim.ui.input({
    prompt = '编辑时间: ',
    default = default_datetime_str,
    completion = nil, -- 不需要补全
  }, function(input)
    -- 用户按下回车后执行的回调函数
    if not input or input == '' then
      return
    end

    -- 5. 将用户修改后的字符串转换回时间戳
    local new_ts_in_seconds = string_to_timestamp(input)
    if not new_ts_in_seconds then
      -- string_to_timestamp 内部已经显示了错误信息
      return
    end

    -- 6. 根据原始格式（秒或毫秒）生成新的时间戳字符串
    local final_ts_str
    if is_millisecond then
      final_ts_str = tostring(new_ts_in_seconds * 1000)
    else
      final_ts_str = tostring(new_ts_in_seconds)
    end

    -- 7. 替换原始文本
    -- 这是一个可靠的方法：在当前行中，用新的时间戳替换光标下的旧时间戳
    local current_line = vim.api.nvim_get_current_line()
    -- 使用 gsub 的第四个参数 1，确保只替换当前行的第一个匹配项
    local new_line, replacements = string.gsub(current_line, cword, final_ts_str, 1)

    if replacements > 0 then
      vim.api.nvim_set_current_line(new_line)
      vim.print(string.format("，时间戳已更新为: %s", final_ts_str))
    else
      vim.notify("替换失败！未在当前行找到原始时间戳。", vim.log.levels.ERROR)
    end
  end)
end


return M
