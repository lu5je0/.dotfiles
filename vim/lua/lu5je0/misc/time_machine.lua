local M = {}

local cnt = 0
local function get_file_name()
  local filename = os.date("%Y-%m-%dT%H:%M:%S-", os.time()) .. cnt .. '.' .. vim.bo.filetype
  cnt = cnt + 1
  return filename
end

return M
