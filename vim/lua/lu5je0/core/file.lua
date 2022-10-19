local M = {}

function M.format_bytes(bytes)
  local units = {'B', 'K', 'M', 'G', 'T'}

  bytes = math.max(bytes, 0)
  local pow = math.floor((bytes and math.log(bytes) or 0) / math.log(1024))
  pow = math.min(pow, #units)

  local value = bytes / (1024 ^ pow)
  value = math.floor((value * 10) + 0.5) / 10

  pow = pow + 1

  return (units[pow] == nil) and (bytes .. 'B') or (value .. units[pow])
end

function M.hunman_readable_file_size(filepath)
  return M.format_bytes(vim.fn.getfsize(filepath))
end

return M
