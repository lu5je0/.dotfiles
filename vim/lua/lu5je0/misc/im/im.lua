---@diagnostic disable: need-check-nil
local M = {}

local state = {
  save_last_ime = require('lu5je0.misc.env-keeper').get('save_last_ime', true)
}

local function toggle_save_last_ime()
  local keeper = require('lu5je0.misc.env-keeper')
  local v = keeper.get('save_last_ime', true)
  if v then
    print("keep last ime disabled")
  else
    print("keep last ime enabled")
  end
  state.save_last_ime = not v
  keeper.set('save_last_ime', state.save_last_ime)
end

local function create_autocmd()
  local group = vim.api.nvim_create_augroup('ime-status', { clear = true })
  
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'CmdlineLeave', 'FocusGained' }, {
    group = group,
    pattern = { '*' },
    callback = function()
      M.normal()
    end
  })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.insert()
    end
  })
end

function M.setup()
  local ime_control = nil
  if vim.fn.has('wsl') == 1 then
    ime_control = require('lu5je0.misc.im.win.ime-control-v2').setup()
  elseif vim.fn.has('mac') == 1 then
    ime_control = require('lu5je0.misc.im.mac.ime-control').setup()
  else
    ime_control = require('lu5je0.misc.im.ssh.ime-control').setup()
  end
  
  local rate_limiter = require('lu5je0.lang.ratelimiter'):create(7, 0.5)
  local timer = nil
  -- timer = require('lu5je0.lang.timer')

  M.normal = rate_limiter:wrap(function()
    if timer ~=nil then timer.begin_timer() end
    ime_control.normal()
    if timer ~=nil then timer.end_timer() end
  end)

  M.insert = rate_limiter:wrap(function()
    if not state.save_last_ime then
      return
    end
    if timer ~=nil then timer.begin_timer() end
    ime_control.insert()
    if timer ~=nil then timer.end_timer() end
  end)

  vim.keymap.set('n', '<leader>vi', toggle_save_last_ime)
  create_autocmd()
end

return M
