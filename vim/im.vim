if !has("mac")
    finish
endif

let s:std_config_path = stdpath("config")
let g:save_last_ime = v:lua.require('misc/env-keeper').get('save_last_ime', '0')

function! ImFuncInit()
if get(g:, "im_init", 0) == 1
    return
endif
let g:im_init = 1
python3 << EOF
import threading

import sys
import time
from os.path import normpath, join
import vim
python_root_dir = vim.eval('s:std_config_path') + "/python"
sys.path.insert(0, python_root_dir)
switcher = None

def im_init():
    import im
    global switcher
    switcher = im.ImSwitcher()

threading.Thread(target=im_init).start()
EOF
endfunction

function! SwitchInsertMode()
    call ImFuncInit()
    if g:save_last_ime == 1
        call libcall(s:std_config_path . "/lib/libinput-source-switcher.dylib", "switchInputSource", py3eval("'com.apple.keylayout.ABC' if switcher is None else switcher.last_ime"))
    else
        call libcall(s:std_config_path . "/lib/libinput-source-switcher.dylib", "switchInputSource", "com.apple.keylayout.ABC")
    endif
endfunction

function! SwitchNormalMode()
call ImFuncInit()
python3 << EOF
if switcher != None:
    switcher.switch_normal_mode()
EOF
endfunction

function! ToggleSaveLastIme()
    let v = v:lua.require('misc/env-keeper').get('save_last_ime', '0')
    if v == '0'
        let g:save_last_ime = 1
        echo "keep last ime enabled"
    else
        let g:save_last_ime = 0
        echo "keep last ime disabled"
    endif
    lua require('misc/env-keeper').set('save_last_ime', tostring(vim.g.save_last_ime))
endfunction

" 无操作自动加载
function! ImFuncJob(timer) abort
    call ImFuncInit()
endfunction
call timer_start(5000, 'ImFuncJob')

command! SwitchNormalMode call SwitchNormalMode()
command! SwitchInsertMode call SwitchInsertMode()
command! ToggleSaveLastIme call ToggleSaveLastIme()

augroup switch_im
    autocmd!
    autocmd InsertLeave * call SwitchNormalMode()
    autocmd InsertEnter * call SwitchInsertMode()
augroup END
