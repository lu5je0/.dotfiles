local M = {}

local py3eval = vim.fn.pyeval

local std_config_path = vim.fn.stdpath('config')

local group = vim.api.nvim_create_augroup('ime-status', { clear = true })

local ffi = require('ffi')

local im_switcher = ffi.load(std_config_path .. '/lib/libinput-source-switcher.dylib')

local ABC_IM_SOURCE_CODE = 'com.apple.keylayout.ABC'

ffi.cdef([[
int switchInputSource(const char *s);
const char* getCurrentInputSourceID();
]])

local switch_to_im = function(im_code)
  im_switcher.switchInputSource(im_code)
end

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

M.python_im_helper_is_init = false

local function init_python_im_helper()
  if M.python_im_helper_is_init then
    return
  end
  vim.cmd(M.py_im_init_script)
  M.python_im_helper_is_init = true
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
    switch_to_im(py_watched_im_source)
  else
    switch_to_im(ABC_IM_SOURCE_CODE)
  end
end

M.switch_normal_mode = function()
  if M.save_last_ime then
    init_python_im_helper()
    py3eval("switch_normal_mode()")
  else
    switch_to_im(ABC_IM_SOURCE_CODE)
  end
end

M.setup = function()
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
  
  M.save_last_ime = require('lu5je0.misc.env-keeper').get('save_last_ime', true)
end

return M
