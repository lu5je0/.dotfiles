local M

function M.is_register_contains_newline(register)
  local s = vim.fn.getreg(register)
  return string.find(s, '\n') ~= nil
end

return M
