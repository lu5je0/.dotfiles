local M = {}

-- local time = vim.uv.hrtime()
-- vim.print((vim.uv.hrtime() - time) / 1000000)

function M.now()
  local timestamp, s = vim.uv.gettimeofday()
  return timestamp * 1000 + math.floor(s / 1000)
end

function M.timer_wrap(fn)
  return function(...)
    local t = M.now()
    local r = fn(...)
    local total = M.now() - t
    print(('total: %sms'):format(total))
    return r
  end
end

function M.measure_fn(fn, cnt)
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
function M.begin_timer()
  now = M.now()
end

function M.end_timer()
  print(M.now() - now)
end

return M
