if !has("mac") && IsWSL() == 1
    let g:im_select_default=1033
endif

" mac下输入法切换问题
if has("mac") && has("gui")
    set noimd
    set imi=2
    set ims=2
endif

" 退出vim时 恢复默认输入法
if !has("gui")
    if has("mac")
        au VimLeave * call im_select#set_im('com.sogou.inputmethod.sogou.pinyin')
    endif
endif

if !has("mac") || has("gui")
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
EOF

function! SwitchToEn()
python3 << EOF

last = im.getCurrentInputSourceID()
im.switchInputSource(mac_im)

EOF
endfunction


function! SwitchToCn()
python3 << EOF

im.switchInputSource(last)

EOF
endfunction

command! SwitchToCn call SwitchToCn()
command! SwitchToEn call SwitchToEn()
