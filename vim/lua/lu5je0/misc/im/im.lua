---@diagnostic disable: need-check-nil
local M = {}

local state = {
  save_last_ime = require('lu5je0.misc.env-keeper').get('save_last_ime', true),
  keeper_enabled = false,
  ime_control = nil
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
  
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'CmdlineLeave' }, {
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

local function set_keeper(enable)
  state.keeper_enabled = enable
  state.ime_control.keeper(state.keeper_enabled)
end

local function config_keeper()
  local ime_control = state.ime_control
  if not ime_control.on_change or not ime_control.should_normalize or not ime_control.keeper then
    return
  end
  
  ime_control.on_change(function(args)
    if state.keeper_enabled and ime_control.should_normalize(args) then
      ime_control.switch_en()
    end
  end)

  local keeper_group = vim.api.nvim_create_augroup('ime-keeper-common', { clear = true })

  vim.api.nvim_create_autocmd({ 'InsertLeave', 'CmdlineLeave', 'TermLeave' }, {
    group = keeper_group,
    pattern = { '*' },
    callback = function()
      set_keeper(true)
    end
  })

  vim.api.nvim_create_autocmd({ 'InsertEnter', 'FocusLost', 'TermEnter', 'CmdlineEnter' }, {
    group = keeper_group,
    pattern = { '*' },
    callback = function()
      set_keeper(false)
    end
  })

  vim.api.nvim_create_autocmd('FocusGained', {
    group = keeper_group,
    pattern = { '*' },
    callback = function()
      set_keeper(true)
      if vim.api.nvim_get_mode().mode == 'n' then
        M.normal()
      end
    end
  })
  
  if vim.api.nvim_get_mode().mode == 'n' then
    set_keeper(true)
  end
end

function M.setup()
  if vim.fn.has('wsl') == 1 then
    state.ime_control = require('lu5je0.misc.im.win.ime-control').setup()
  elseif vim.fn.has('mac') == 1 then
    state.ime_control = require('lu5je0.misc.im.mac.ime-control').setup()
  else
    state.ime_control = require('lu5je0.misc.im.ssh.ime-control').setup()
  end
  
  local rate_limiter = require('lu5je0.lang.ratelimiter'):create(7, 0.5)
  local timer = nil
  -- timer = require('lu5je0.lang.timer')

  M.normal = rate_limiter:wrap(function()
    if timer ~=nil then timer.begin_timer() end
    state.ime_control.normal()
    if timer ~=nil then timer.end_timer() end
  end)

  M.insert = rate_limiter:wrap(function()
    if not state.save_last_ime then
      return
    end
    if timer ~=nil then timer.begin_timer() end
    state.ime_control.insert()
    if timer ~=nil then timer.end_timer() end
  end)
  
  vim.keymap.set('n', '<leader>vi', toggle_save_last_ime)
  create_autocmd()

  config_keeper()
end

return M
