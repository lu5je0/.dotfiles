local M = {}

M.now = function()
  local timestamp, s = vim.loop.gettimeofday()
  return timestamp * 1000 + math.floor(s / 1000)
end

M.measure = function(fn, cnt)
  if not cnt then
    cnt = 10000
  end
  
  local t = M.now()
  for _ = 1, cnt do
    fn()
  end
  local total = M.now() - t
  print(('total: %sms, avg: %.4fms'):format(total, total / cnt))
end

return M
