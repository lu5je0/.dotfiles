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

return M
