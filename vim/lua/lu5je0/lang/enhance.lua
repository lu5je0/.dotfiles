function string.startswith(self, str)
  return string.sub(self, 1, string.len(str)) == str
end

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

function table:remove_by_value(v)
  for i, item in ipairs(self) do
    if item == v then
      table.remove(self, i)
    end
  end
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
  print(vim.inspect(arg, { depth = depth }))
end

_G.log = require('plenary.log')
