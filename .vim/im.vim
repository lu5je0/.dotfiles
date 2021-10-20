if has("gui")
    " macvim
    if has("mac") 
        set noimd
        set imi=2
        set ims=2
    endif
    finish
endif

if !has("mac") && (has("win32") || IsWSL())
    let g:im_select_default=1033
    " 退出vim时 恢复默认输入法
    augroup vim_leave_group
        autocmd!
        autocmd VimLeave * call im_select#set_im('2052')
    augroup END
endif

" ##################################
" #              mac               #
" ##################################
if !has("mac")
    finish
endif

augroup switch_im
    autocmd!
    autocmd InsertLeave * call SwitchNormalMode()
    autocmd InsertEnter * call SwitchInsertMode()
augroup END

let s:plugin_root_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let g:save_last_ime = 0

function! ImFuncInit()
python3 << EOF
import threading

import sys
import time 
from os.path import normpath, join
import vim
python_root_dir = vim.eval('s:plugin_root_dir') + "/python"
sys.path.insert(0, python_root_dir)
switcher = None

def im_init():
    import im
    global switcher
    switcher = im.ImSwitcher()

threading.Thread(target=im_init).start()
EOF
endfunction

call ImFuncInit()

function! SwitchInsertMode()
    if g:save_last_ime == 1
        call libcall(s:plugin_root_dir . "/lib/libinput-source-switcher.dylib", "switchInputSource", py3eval("'com.apple.keylayout.ABC' if switcher is None else switcher.last_ime"))
    else
        call libcall(s:plugin_root_dir . "/lib/libinput-source-switcher.dylib", "switchInputSource", "com.apple.keylayout.ABC")
    endif
endfunction

function! SwitchNormalMode()
python3 << EOF
if switcher != None:
    switcher.switch_normal_mode()
EOF
endfunction

function! ToggleSaveLastIme()
    if g:save_last_ime == 0
        let g:save_last_ime = 1
        echo "keep last ime enabled"
    else
        let g:save_last_ime = 0
        echo "keep last ime disabled"
    endif
endfunction

command! SwitchNormalMode call SwitchNormalMode()
command! SwitchInsertMode call SwitchInsertMode()
command! ToggleSaveLastIme call ToggleSaveLastIme()
