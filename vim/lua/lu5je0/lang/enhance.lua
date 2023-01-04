function string:split(delimiter)
  local result = {}
  local from = 1
  local delim_from, delim_to = string.find(self, delimiter, from)
  while delim_from do
    table.insert(result, string.sub(self, from, delim_from - 1))
    from = delim_to + 1
    delim_from, delim_to = string.find(self, delimiter, from)
  end
  table.insert(result, string.sub(self, from))
  return result
end

function table:contain(value)
  if self and type(self) == 'table' and value then
    for _, v in ipairs(self) do
      if v == value then
        return true
      end
    end
    return false
  end
  return false
end

function _G.dump(arg, depth)
  return vim.inspect(arg, { depth = depth })
end

local original_has = vim.fn.has
vim.fn.has = function(feature)
  local r = original_has(feature)
  
  if feature == 'gui' then
    return vim.g.gonvim_running or r
  end
  
  return r
end
