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
    autocmd InsertLeave * call SwitchInsertMode()
    autocmd InsertEnter * call SwitchNormalMode()
augroup END

let s:plugin_root_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

function! ImFuncInit()
python3 << EOF
import threading
import sys
from os.path import normpath, join
import vim

python_root_dir = vim.eval('s:plugin_root_dir') + "/python"
sys.path.insert(0, python_root_dir)
import im

switcher = im.ImSwitcher()
EOF
endfunction
call ImFuncInit()

function! SwitchInsertMode()
python3 << EOF
if switcher != None:
    switcher.switch_normal_mode()
EOF
endfunction


function! SwitchNormalMode()
python3 << EOF
if switcher != None:
    switcher.swith_insert_mode()
EOF
endfunction

function! ToggleSaveLastIme()
python3 << EOF
if switcher != None:
    switcher.toggle_save_last_ime()
EOF
endfunction

command! SwitchNormalMode call SwitchNormalMode()
command! SwitchInsertMode call SwitchInsertMode()
command! ToggleSaveLastIme call ToggleSaveLastIme()
