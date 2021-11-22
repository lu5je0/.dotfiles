local M = {}

function M.load_plugin(plugin)
  vim.cmd("PackerLoad " .. plugin)
end

return M
