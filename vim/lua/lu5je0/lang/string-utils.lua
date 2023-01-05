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

M.starts_with = function(str, prefix)
  return string.sub(str, 1, string.len(prefix)) == prefix
end

M.ends_with = function(str, suffix)
  return suffix == "" or str:sub(-#suffix) ==suffix
end

M.contains = function(old, new)
  return old:find(new) ~= nil
end

return M
