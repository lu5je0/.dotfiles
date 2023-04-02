local M = {}

function M.load_plugin(plugin)
  vim.cmd('Lazy load ' .. plugin)
end

return M
