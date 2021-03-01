if has("gui")
    " macvim
    if has("mac") 
        set noimd
        set imi=2
        set ims=2
    endif
    finish
endif

if has("win32") || IsWSL()
    let g:im_select_default=1033
endif

" 退出vim时 恢复默认输入法
if has("win32") || IsWSL()
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
    autocmd InsertLeave * call SwitchToEn()
    autocmd InsertEnter * call SwitchToCn()
augroup END

let s:plugin_root_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')
python3 << EOF
import sys
from os.path import normpath, join
import vim
python_root_dir = vim.eval('s:plugin_root_dir') + "/python"
sys.path.insert(0, python_root_dir)
import im
import importlib
importlib.reload(im)

mac_im = 'com.apple.keylayout.ABC'
last = 'com.apple.keylayout.ABC'
switcher = im.ImSwitcher()
EOF

function! SwitchToEn()
python3 << EOF

# last = switcher.getCurrentInputSourceID()
switcher.switchInputSource(mac_im)

EOF
endfunction


function! SwitchToCn()
python3 << EOF

switcher.switchInputSource(last)

EOF
endfunction

command! SwitchToCn call SwitchToCn()
command! SwitchToEn call SwitchToEn()
