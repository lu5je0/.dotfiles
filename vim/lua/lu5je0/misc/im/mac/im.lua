local M = {}

local py3eval = vim.fn.pyeval

local ABC_IM_SOURCE_CODE = 'com.apple.keylayout.ABC'

local std_config_path = vim.fn.stdpath('config')

local im_switcher = (function()
  local ffi = require('ffi')
  local switcher = ffi.load(std_config_path .. '/lib/libinput-source-switcher.dylib')
  ffi.cdef([[
  int switchInputSource(const char *s);
  const char* getCurrentInputSourceID();
  ]])
  
  return {
    switch_to_im = function(im_code)
      ---@diagnostic disable-next-line: undefined-field
      switcher.switchInputSource(im_code)
    end
  }
end)()

local group = vim.api.nvim_create_augroup('ime-status', { clear = true })

M.py_im_init_script = ([[
python3 << EOF
import threading

import sys
import time
from os.path import normpath, join
import vim
python_root_dir = "%s" + "/python"
sys.path.insert(0, python_root_dir)
switcher = None

def im_init():
  import im
  global switcher
  switcher = im.ImSwitcher()

def switch_normal_mode():
  if switcher != None:
    switcher.switch_normal_mode(True)

threading.Thread(target=im_init).start()
EOF
]]):format(std_config_path)

local python_im_helper_is_init = false
local function init_python_im_helper()
  if python_im_helper_is_init then
    return
  end
  vim.cmd(M.py_im_init_script)
  python_im_helper_is_init = true
end

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

M.switch_insert_mode = function()
  if M.save_last_ime then
    init_python_im_helper()
    local py_watched_im_source = py3eval("'com.apple.keylayout.ABC' if switcher is None else switcher.last_ime")
    im_switcher.switch_to_im(tostring(py_watched_im_source))
  else
    im_switcher.switch_to_im(ABC_IM_SOURCE_CODE)
  end
end

M.switch_normal_mode = function()
  if M.save_last_ime then
    init_python_im_helper()
    py3eval("switch_normal_mode()")
  else
    im_switcher.switch_to_im(ABC_IM_SOURCE_CODE)
  end
end

M.setup = function()
  M.save_last_ime = require('lu5je0.misc.env-keeper').get('save_last_ime', true)
  
  vim.api.nvim_create_autocmd('InsertLeave', {
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
