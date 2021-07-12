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
    autocmd InsertLeave * call SwitchToEn()
    autocmd InsertEnter * call SwitchToCn()
augroup END

let s:plugin_root_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

function! ImFuncInit()
python3 << EOF
import threading

mac_im = None
last = None
switcher = None

def im_init(path):
    global mac_im
    global last
    global switcher

    import sys
    from os.path import normpath, join
    import vim
    python_root_dir = path + "/python"
    sys.path.insert(0, python_root_dir)
    import im
    mac_im = 'com.apple.keylayout.ABC'
    last = 'com.apple.keylayout.ABC'
    switcher = im.ImSwitcher()

path = vim.eval('s:plugin_root_dir')
threading.Thread(target=im_init, args=[path]).start()
EOF
endfunction

call ImFuncInit()

function! SwitchToEn()
python3 << EOF
# last = switcher.getCurrentInputSourceID()
if switcher != None:
    switcher.switchInputSource(mac_im)
EOF
endfunction


function! SwitchToCn()
python3 << EOF
if switcher != None:
    switcher.switchInputSource(last)
EOF
endfunction

command! SwitchToCn call SwitchToCn()
command! SwitchToEn call SwitchToEn()
