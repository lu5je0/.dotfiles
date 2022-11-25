local M = {}

local hex_to_char = function(s)
  return string.char(tonumber(s, 16))
end

M.url_decode = function (s)
  return s:gsub("%%(%x%x)", hex_to_char)
end

return M
