local M = {}

local std_config_path = vim.fn.stdpath("config")

local is_im_switcher_server_init = false

local env_keeper = require('lu5je0.misc.env-keeper').keeper({ save_last_ime = '0' })

local im_py_func_init_function_text = [[
function! ImFuncInit()
python3 << EOF
import threading

import sys
import time
from os.path import normpath, join
import vim
python_root_dir = "%s/python"
sys.path.insert(0, python_root_dir)
switcher = None

def im_init():
    import im
    global switcher
    switcher = im.ImSwitcher()

threading.Thread(target=im_init).start()
EOF
endfunction

function! ImSwitchNormal()
python3 << EOF
if switcher != None:
  switcher.switch_normal_mode(True)
EOF
endfunction
]]
vim.cmd(im_py_func_init_function_text:format(std_config_path))

local im_switcher_server_init = function()
  if env_keeper.save_last_ime == '1' and is_im_switcher_server_init then
    return
  end
  vim.fn.ImFuncInit()
  is_im_switcher_server_init = true
end

local function toggle_save_last_ime()
  if env_keeper.save_last_ime == '0' then
    env_keeper.save_last_ime = '1'
    print('keep last ime enabled')
  elseif env_keeper.save_last_ime == '1' then
    env_keeper.save_last_ime = '0'
    print('keep last ime disabled')
  end
end

local function switch_to_normal_mode()
  im_switcher_server_init()

  if env_keeper.save_last_ime == '1' then
    vim.fn.ImSwitchNormal()
  else
    vim.fn.libcall(std_config_path .. "/lib/libinput-source-switcher.dylib", "switchInputSource", "com.apple.keylayout.ABC")
  end
end

local function switch_to_insert_mode()
  im_switcher_server_init()

  local last_ime = vim.fn.py3eval("'com.apple.keylayout.ABC' if switcher is None else switcher.last_ime")
  vim.fn.libcall(std_config_path .. "/lib/libinput-source-switcher.dylib", "switchInputSource", last_ime)
end

M.setup = function()
  local group = vim.api.nvim_create_augroup('ime-status', { clear = true })
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      switch_to_normal_mode()
    end
  })

  -- vim.api.nvim_create_autocmd('InsertEnter', {
  --   group = group,
  --   pattern = { '*' },
  --   callback = function()
  --     switch_to_insert_mode()
  --   end
  -- })


  local opts = { noremap = true, silent = true, desc = 'im.lua' }
  vim.keymap.set('n', '<leader>vi', toggle_save_last_ime, opts)
end

return M
