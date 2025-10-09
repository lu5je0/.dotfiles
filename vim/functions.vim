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

function! SetOperation(...)
call PyFuncInit()
python3 << EOF
functions.set_operation(vim.eval("a:000"))
EOF
endfunction

function! SetOperationCompletion(A, L, P)
  " 定义集合操作的候选列表
  " 交集 intersection           A ∩ B	同时属于A和B
  " 差集 difference             A - B	属于A但不属于B
  " 并集 union                  A ∪ B	属于A或B
  " 补集 complement 	        A'	    属于全集，不属于A
  " 对称差 symmetric-difference	A △ B	属于A或B，但不同时属于A和B
  let completions = ['intersection', 'difference', 'union', 'complement', 'symmetric-difference']

  " 使用 complete() 函数设置自动补全的候选项
  return filter(completions, 'v:val =~ "^" . a:A')
endfunction
command! -complete=customlist,SetOperationCompletion -nargs=* SetOperation call SetOperation(<f-args>)

function! KeepLines(...)
call PyFuncInit()
python3 << EOF
functions.keepLines(vim.eval("a:000"))
EOF
endfunction
command! -nargs=* KeepLines call KeepLines(<f-args>)

function! ReplaceAllTimestamp(...)
call PyFuncInit()
python3 << EOF
functions.replace_all_timestamp(vim.eval("a:000"))
EOF
endfunction
command! -nargs=* TimestampReplaceAll call ReplaceAllTimestamp(<f-args>)

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
