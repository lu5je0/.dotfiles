local M = {}

local hex_to_char = function(s)
  return string.char(tonumber(s, 16))
end

M.url_decode = function(s)
  return s:gsub("%%(%x%x)", hex_to_char)
end

M.is_blank = function(s)
  return s == nil or s:match("%S") == nil
end

M.trim = function(s)
  return s:match"^%s*(.*)":match"(.-)%s*$"
end

return M
