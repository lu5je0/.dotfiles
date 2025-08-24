local M = {}

local rate_limiter = require('lu5je0.lang.ratelimiter'):create(7, 0.5)
local group = vim.api.nvim_create_augroup('ime-status', { clear = true })

local function write(osc)
  local success = false
  if vim.fn.filewritable('/dev/fd/2') == 1 then
    success = vim.fn.writefile({osc}, '/dev/fd/2', 'b') == 0
  else
    success = vim.fn.chansend(vim.v.stderr, osc) > 0
  end
  return success
end

M.disable_ime = rate_limiter:wrap(function()
  write(string.format("\27]1337;SetUserVar=%s=%s\7", "ime", require('lu5je0.misc.base64').encode("en")))
end)

-- M.enable_ime = rate_limiter:wrap(function()
--   if M.save_last_ime then
--     -- TODO
--   end
-- end)
--
-- function M.toggle_save_last_ime()
-- end

M.switch_normal_mode = rate_limiter:wrap(function()
  M.disable_ime()
end)

function M.setup()
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.switch_normal_mode()
    end
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.switch_normal_mode()
    end
  })
end

return M
