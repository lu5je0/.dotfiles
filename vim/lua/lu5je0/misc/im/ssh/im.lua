local M = {}

local rate_limiter = require('lu5je0.lang.ratelimiter'):create(7, 0.5)

M.disable_ime = rate_limiter:wrap(function()
  print('1')
end)

M.enable_ime = rate_limiter:wrap(function()
  if M.save_last_ime then
  end
end)

function M.toggle_save_last_ime()
end


function M.setup()
end

return M
