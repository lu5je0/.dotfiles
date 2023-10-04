local M = {}

local string_utils = require('lu5je0.lang.string-utils')

local encode_command_creater = require('lu5je0.misc.encode-command-creater')

local function is_number(str)
  if not str then
    return false
  end
  if str:match("^%d+$") then
    return true
  else
    return false
  end
end

local function timestamp_to_date(timestamp)
  if not is_number(timestamp) then
    return timestamp
  end

  local len = #tostring(timestamp)
  while len > 10 do
    timestamp = timestamp / 10
    len = #tostring(timestamp)
  end
  return os.date("%Y-%m-%d %H:%M:%S", timestamp)
end

function M.encode(str)
  local pattern = "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
  local year, month, day, hour, min, sec = str:match(pattern)
  local converted_time = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
  return tostring(converted_time)
end

function M.toggle(data)
  if string_utils.contains(data, ':') then
    return M.encode(data)
  else
    return timestamp_to_date(data)
  end
end

function M.create_command()
  encode_command_creater.create_encode_command_by_type('TimestampToggle', M.toggle, M.toggle)
end

return M
