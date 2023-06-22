local M = {}

function M.url_decode(s)
  return s:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end)
end

function M.is_blank(s)
  return s == nil or s:match("%S") == nil
end

function M.trim(s)
  return s:match "^%s*(.*)":match "(.-)%s*$"
end

--- @param str string
--- @param prefix string
function M.starts_with(str, prefix)
  if prefix == nil then
    return true
  end
  return string.sub(str, 1, string.len(prefix)) == prefix
end

--- @param str string
--- @param suffix string
function M.ends_with(str, suffix)
  return suffix == "" or str:sub(- #suffix) == suffix
end

--- @param old string
--- @param new string
function M.contains(old, new)
  return old:find(new) ~= nil
end

function M.split(str, delimiter)
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
