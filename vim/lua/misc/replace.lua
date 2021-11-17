local M = {}

function M.replace()
  local target = vim.fn.input("replace with:")
  vim.cmd(":%s/" .. vim.call('visual#visual_selection') .. "/" .. target .. "/g")
end

return M
