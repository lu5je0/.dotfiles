local M = {}

local group = vim.api.nvim_create_augroup('ime-status', { clear = true })
local rate_limiter = require('lu5je0.lang.ratelimiter'):create(7, 0.5)
local timer = require('lu5je0.lang.timer')

-- local STD_PATH = vim.fn.stdpath('config')

-- 80ms左右
-- local DISABLE_IME = STD_PATH .. '/lib/toDisableIME.exe'
-- local ENABLE_IME = STD_PATH .. '/lib/toEnableIME.exe'

-- 这样比较快 40ms左右
local DISABLE_IME = '/mnt/d/bin/toDisableIME.exe'
local ENABLE_IME = '/mnt/d/bin/toEnableIME.exe'

M.disable_ime = rate_limiter:wrap(function()
  vim.loop.new_thread(function(path)
    io.popen(path .. ' 2>&1 1>/dev/null'):close()
  end, DISABLE_IME)
end)

M.enable_ime = rate_limiter:wrap(function()
  if M.save_last_ime then
   vim.loop.new_thread(function(path)
      io.popen(path .. ' 2>&1 1>/dev/null'):close()
    end, ENABLE_IME)
  end
end)

function M.toggle_save_last_ime()
  local keeper = require('lu5je0.misc.env-keeper')
  local v = keeper.get('save_last_ime', true)
  if v then
    print("keep last ime disabled")
  else
    print("keep last ime enabled")
  end
  M.save_last_ime = not v
  keeper.set('save_last_ime', M.save_last_ime)
end

local function create_autocmd()
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.disable_ime()
    end
  })
  
  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.disable_ime()
    end
  })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.enable_ime()
    end
  })
end

function M.setup()
  M.save_last_ime = require('lu5je0.misc.env-keeper').get('save_last_ime', true)
  create_autocmd()
  vim.keymap.set('n', '<leader>vi', M.toggle_save_last_ime)
end

return M
