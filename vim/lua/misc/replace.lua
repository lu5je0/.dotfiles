local M = {}

function M.replace()
  local target = vim.fn.input("replace with:")

  target:gsub("/", "\\/")

  local r = ":%s/" .. vim.call('visual#visual_selection') .. "/" .. target .. "/g"
  print(r)
  vim.cmd(r)
end

return M
