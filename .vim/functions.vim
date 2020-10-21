" 在gj和j之间切换
function! ToggleMouse()
    if !exists("g:ToggleMouse")
        let g:ToggleMouse = "a"
    endif

    if &mouse == ""
        let &mouse = g:ToggleMouse
        echo "Mouse is for Vim (" . &mouse . ")"
    else
        let g:ToggleMouse = &mouse
        let &mouse=""
        echo "Mouse is for terminal"
    endif
endfunction

" 在gj和j之间切换
function! ToggleDiff()
    if !exists("g:ToggleDiff")
        let g:ToggleDiff = 0
    endif
    if g:ToggleDiff == 0
        windo difft
        let g:ToggleDiff = 1
        echo "diff on"
    else
        windo diffo
        let g:ToggleDiff = 0
        echo "diff off"
    endif
endfunction

function! IsVisualMode()
    if mode() == "v"
        return "'<,'>"
    else
        return ""
    endif
endfunction

function! ToggleWrap()
    if !exists("g:ToggleWrapStauts")
        let g:ToggleWrapStauts = 0
    endif
    if g:ToggleWrapStauts == 0
        let g:ToggleWrapStauts = 1
        set wrap!
        echo "wrap"
    else
        set wrap!
        let g:ToggleWrapStauts = 0
        echo "unwrap"
    endif
endfunction

function! ToggleGj()
    if !exists("g:ToggleGjStauts")
        let g:ToggleGjStauts = 0
    endif
    if g:ToggleGjStauts == 0
        nmap j gj
        nmap k gk
        let g:ToggleGjStauts = 1
        echo "gj is enable"
    else
        unmap j
        unmap k
        let g:ToggleGjStauts = 0
        echo "gj is disable"
    endif
endfunction

function! LargeFile()
    " file is large from 5MB
    syntax off
    autocmd VimEnter * echo "The file is larger than " . g:LargeFile . " MB, so some options are changed (see .vimrc for details)."
endfunction

function! IsWSL()
    if exists("g:isWsl")
        return g:isWsl
    endif

    if has("unix")
        let lines = readfile("/proc/version")
        if lines[0] =~ "Microsoft"
            let g:isWsl=1
            return 1
        endif
    endif
    let g:isWsl=0
    return 0
endfunction

let s:plugin_root_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

python3 << EOF
import sys
from os.path import normpath, join
import vim
python_root_dir = vim.eval('s:plugin_root_dir') + "/python"
sys.path.insert(0, python_root_dir)
import functions
import importlib
importlib.reload(functions)
EOF

function! KeepLines(...)
python3 << EOF
import vim
functions.keepLines(vim.eval("a:000"))
EOF
endfunction
command! -nargs=* KeepLines call KeepLines(<f-args>)

function! DelLines(...)
python3 << EOF
import vim
functions.delLines(vim.eval("a:000"))
EOF
endfunction
command! -nargs=* DelLines call DelLines(<f-args>)

function! KeepMatchs(pattern)
python3 << EOF
import vim
functions.keepMatchs(vim.eval("a:pattern"))
EOF
endfunction
command! -nargs=1 KeepMatchs call KeepMatchs(<f-args>)
