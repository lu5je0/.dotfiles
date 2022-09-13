local M = {}
local visual_core_api = require('lu5je0.core.visual')

local function get_timestamp()
  if vim.api.nvim_get_mode().mode == 'v' then
    return visual_core_api.selected_text()
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

M.show_in_date = function()
  print(parse(get_timestamp()))
end

return M
