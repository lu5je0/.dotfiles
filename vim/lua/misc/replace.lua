local M = {}

function M.replace()
  local target = vim.fn.input("replace with:")

  local source = vim.call('visual#visual_selection')
  source = string.gsub(source, "/", "\\/")

  local r = ":%s/" .. source .. "/" .. target .. "/g"
  print(r)
  vim.cmd(r)
end

return M
