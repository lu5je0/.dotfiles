local M = {}

M.valid_buffers = function()
  local bufs = require("bufferline.utils").get_valid_buffers()
  -- local bufs = vim.api.nvim_list_bufs()
  return bufs
end

return M
