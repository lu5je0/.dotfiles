local Stack = {}
local tinsert = table.insert

function Stack:create()
  local t = {}
  setmetatable(t, {__index = self})
  return t
end

function Stack:push(...)
  local arg = {...}
  self.dataTb = self.dataTb or {}
  if next(arg) then
    for i = 1, #arg do
      tinsert(self.dataTb, arg[i])
    end
  end
end

function Stack:pop(num)
  num = num or 1
  assert(num > 0, "num必须为正整数")
  local popTb = {}
  for _ = 1, num do
    tinsert(popTb, self.dataTb[#self.dataTb])
    table.remove(self.dataTb)
  end
  return unpack(popTb)
end

function Stack:list()
  for i = 1, #self.dataTb do
    print(i, self.dataTb[i])
  end
end

function Stack:count()
  if self.dataTb == nil then
    return 0
  end
  return #self.dataTb
end

return Stack
