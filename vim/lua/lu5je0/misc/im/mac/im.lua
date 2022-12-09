local M = {}

local ABC_IM_SOURCE_CODE = 'com.apple.keylayout.ABC'

local std_config_path = vim.fn.stdpath('config')

local rate_limiter = require('lu5je0.lang.ratelimiter'):create(7, 0.5)

local im_switcher = (function()
  local ffi = require('ffi')
  local xkb_switch_lib = ffi.load(std_config_path .. '/lib/XkbSwitchLib.lib')
  ffi.cdef([[
  const char* Xkb_Switch_getXkbLayout();
  void Xkb_Switch_setXkbLayout(const char *s);
  ]])
  
  return {
    switch_to_im = function(im_code)
      if im_code == nil then
        return
      end
      ---@diagnostic disable-next-line: undefined-field
      xkb_switch_lib.Xkb_Switch_setXkbLayout(im_code)
    end,
    get_im = function()
      ---@diagnostic disable-next-line: undefined-field
      return ffi.string(xkb_switch_lib.Xkb_Switch_getXkbLayout())
    end
  }
end)()

local group = vim.api.nvim_create_augroup('ime-status', { clear = true })

M.switch_to_en = function()
  im_switcher.switch_to_im(ABC_IM_SOURCE_CODE)
end

M.toggle_save_last_ime = function()
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

M.switch_insert_mode = rate_limiter:wrap(function()
  if M.save_last_ime then
    im_switcher.switch_to_im(M.last_ime)
  else
    im_switcher.switch_to_im(ABC_IM_SOURCE_CODE)
  end
end)

M.switch_normal_mode = rate_limiter:wrap(function()
  if M.save_last_ime then
    M.last_ime = im_switcher.get_im()
  end
  im_switcher.switch_to_im(ABC_IM_SOURCE_CODE)
end)

M.setup = function()
  M.save_last_ime = require('lu5je0.misc.env-keeper').get('save_last_ime', true)
  
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

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.switch_insert_mode()
    end
  })
  
  vim.keymap.set('n', '<leader>vi', M.toggle_save_last_ime)
end

return M
