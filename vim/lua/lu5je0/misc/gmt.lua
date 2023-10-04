local M = {}

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

function M.decode(data)
  return timestamp_to_date(data)
end

function M.create_command()
  encode_command_creater.create_encode_command_by_type('TimestampDecode', M.decode, M.decode)

  encode_command_creater.create_encode_command_by_type('TimestampEncode', M.encode, M.encode)
end

return M
