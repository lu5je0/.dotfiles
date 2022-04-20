local M = {}

M.compress = function()
  vim.cmd(':%!jq -c')
end

M.format = function()
  vim.cmd(':%!jq')
end

return M
