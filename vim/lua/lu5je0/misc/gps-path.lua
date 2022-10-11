-- todo

local M = {}

M.path = function()
  return require('jsonpath').get()
end

M.is_available = function()
  return true
end

return M
