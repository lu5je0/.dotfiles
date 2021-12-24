function string.startswith(self, str)
  return string.sub(self, 1, string.len(str)) == str
end

function table.dump(o)
  if type(o) == 'table' then
    local s = '{ '
    for k, v in pairs(o) do
      if type(k) ~= 'number' then
        k = '"' .. k .. '"'
      end
      s = s .. '[' .. k .. '] = ' .. table.dump(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

function string:split(delimiter)
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find( self, delimiter, from  )
  while delim_from do
    table.insert( result, string.sub( self, from , delim_from-1 ) )
    from  = delim_to + 1
    delim_from, delim_to = string.find( self, delimiter, from  )
  end
  table.insert( result, string.sub( self, from  ) )
  return result
end

function table.find(t, value)
  if t and type(t) == 'table' and value then
    for _, v in ipairs(t) do
      if v == value then
        return true
      end
    end
    return false
  end
  return false
end

function _G.dump(...)
  local objects = vim.tbl_map(vim.inspect, { ... })
  print(unpack(objects))
end

_G.log = require('plenary.log')

function string.escape_pattern(text)
  return text:gsub('([^%w])', '%%%1')
end
