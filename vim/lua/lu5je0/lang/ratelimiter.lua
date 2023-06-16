local RateLimiter = {}

local timer = require('lu5je0.lang.timer')

function RateLimiter:create(limit, second)
  local t = {}
  setmetatable(t, { __index = self })
  t.limit = limit
  t.second = second
  t.queue = {}
  return t
end

function RateLimiter:get()
  local now = timer.now()
  
  for i = #self.queue, 1, -1 do
    if #self.queue > self.limit or ((now - self.queue[i]) / 1000) > self.second then
      table.remove(self.queue, i)
    end
  end
  
  if #self.queue < self.limit then
    table.insert(self.queue, now)
    return true
  end
  
  return false
end

function RateLimiter:wrap(fn, timing)
  timing = timing or false
  return function(...)
    local t = nil
    if timing then
      t = timer.now()
    end
    
    local r = nil
    if self:get() then
      r = fn(...)
    end
    
    if timing then
      print(('cost %.1f'):format(timer.now() - t))
    end
    return r
  end
end

return RateLimiter
