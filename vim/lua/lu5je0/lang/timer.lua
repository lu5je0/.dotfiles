local M = {}

M.now = function()
  local timestamp, s = vim.loop.gettimeofday()
  return timestamp * 1000 + math.floor(s / 1000)
end

M.timer_wrap = function(fn)
  return function(...)
    local t = M.now()
    local r = fn(...)
    local total = M.now() - t
    print(('total: %sms'):format(total))
    return r
  end
end

M.measure_fn = function(fn, cnt)
  if not cnt then
    cnt = 100
  end
  
  local t = M.now()
  for _ = 1, cnt do
    fn()
  end
  local total = M.now() - t
  print(('total: %sms, avg: %.4fms'):format(total, total / cnt))
end

local now
M.begin_timer = function()
  now = M.now()
end

M.end_timer = function()
  print(M.now() - now)
end

return M
