local M = {}

local ffi = require('ffi')

local im_switcher = ffi.load(vim.fn.stdpath('config') .. '/lib/libinput-source-switcher.dylib')

local en_im_code = 'com.apple.keylayout.ABC'

ffi.cdef([[
int switchInputSource(const char *s);
const char* getCurrentInputSourceID();
]])

M.switch = function(im_code)
  im_switcher.switchInputSource(im_code)
end

M.get_current_im_code = function()
  return ffi.string(im_switcher.getCurrentInputSourceID())
end

M.last_im_code = nil

M.bootstrap = function()
  local group = vim.api.nvim_create_augroup('im_switch_group', { clear = true })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = { '*' },
    callback = function()
      if M.last_im_code ~= nil and M.last_im_code ~= en_im_code then
        M.switch(M.last_im_code)
      end
    end,
  })

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.last_im_code = M.get_current_im_code()
      print(M.last_im_code)
      M.switch(en_im_code)
    end,
  })
end

return M
