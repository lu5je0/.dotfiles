let s:plugin_root_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

let g:py_func_init = 0

function! PyFuncInit()
if g:py_func_init == 1
    return
endif

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
let g:py_func_init = 1
endfunction

function! KeepLines(...)
call PyFuncInit()
python3 << EOF
functions.keepLines(vim.eval("a:000"))
EOF
endfunction
command! -nargs=* KeepLines call KeepLines(<f-args>)

function! DelLines(...)
call PyFuncInit()
python3 << EOF
functions.delLines(vim.eval("a:000"))
EOF
endfunction
command! -nargs=* DelLines call DelLines(<f-args>)

function! KeepMatchs(pattern)
call PyFuncInit()
python3 << EOF
functions.keepMatchs(vim.eval("a:pattern"))
EOF
endfunction
command! -nargs=1 KeepMatchs call KeepMatchs(<f-args>)

" A function to clear the undo history
function! <SID>ForgetUndo()
    let old_undolevels = &undolevels
    set undolevels=-1
    exe "normal a \<BS>\<Esc>"
    let &undolevels = old_undolevels
    unlet old_undolevels
endfunction
command -nargs=0 ClearUndo call <SID>ForgetUndo()
