function string.startswith(self, str)
  return string.sub(self, 1 , string.len(str)) == str
end

function table.dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. table.dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

function _G.dump(...)
    local objects = vim.tbl_map(vim.inspect, {...})
    print(unpack(objects))
end

function string.escape_pattern(text)
    return text:gsub("([^%w])", "%%%1")
end
