local M = {}

M.url_decode = function(s)
  return s:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end)
end

M.is_blank = function(s)
  return s == nil or s:match("%S") == nil
end

M.trim = function(s)
  return s:match "^%s*(.*)":match "(.-)%s*$"
end

--- @param str string
--- @param prefix string
M.starts_with = function(str, prefix)
  return string.sub(str, 1, string.len(prefix)) == prefix
end

--- @param str string
--- @param suffix string
M.ends_with = function(str, suffix)
  return suffix == "" or str:sub(- #suffix) == suffix
end

--- @param old string
--- @param new string
M.contains = function(old, new)
  return old:find(new) ~= nil
end

M.split = function(str, delimiter)
  local result = {}
  local from = 1
  local delim_from, delim_to = string.find(str, delimiter, from)
  while delim_from do
    table.insert(result, string.sub(str, from, delim_from - 1))
    from = delim_to + 1
    delim_from, delim_to = string.find(str, delimiter, from)
  end
  table.insert(result, string.sub(str, from))
  return result
end

return M
