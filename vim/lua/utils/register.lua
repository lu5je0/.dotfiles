local M

M.is_register_contains_newline = function(register)
  local s = vim.fn.getreg(register)
  return string.find(s, '\n') ~= nil
end

return M
