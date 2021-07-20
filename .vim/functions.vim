function! QuitForce()
    if confirm("Quit all buffers without save?", "&No\n&Yes") != 2
        return
    endif
    qa!
endfunction

" Toggle signcolumn. Works on vim>=8.1 or NeoVim
function! ToggleSignColumn()
    if !exists("b:signcolumn_on") || b:signcolumn_on
        set signcolumn=yes
        let b:signcolumn_on=0
        echo "signcolumn=yes"
    else
        set signcolumn=number
        let b:signcolumn_on=1
        echo "signcolumn=number"
    endif
endfunction

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

function! TogglePaste()
    if !exists("g:TogglePaste")
        let g:TogglePaste = 0
    endif
    if g:TogglePaste == 0
        nmap p p=`]
        set paste!
        let g:TogglePaste = 1
        echo "paste mode"
    else
        unmap p
        set paste!
        let g:TogglePaste = 0
        echo "disable paste mode"
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
        map j gj
        map k gk
        let g:ToggleGjStauts = 1
        echo "wrap"
    else
        set wrap!
        let g:ToggleWrapStauts = 0
        unmap j
        unmap k
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

function! KeepLines(...)
call PyFuncInit()
python3 << EOF
functions.keepLines(vim.eval("a:000"))
EOF
endfunction
command! -nargs=* KeepLines call KeepLines(<f-args>)

function! JsonFormat(...)
call PyFuncInit()
python3 << EOF
functions.jsonFormat()
EOF
endfunction
command! -nargs=* JsonFormat call JsonFormat(<f-args>)

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

function! CloseBuffer()
call PyFuncInit()
python3 << EOF
functions.closeBuffer()
EOF
endfunction
command! CloseBuffer call CloseBuffer()

function! FileSize()
  let bytes = getfsize(expand('%:p'))
  if (bytes >= 1024)
    let kbytes = bytes / 1024
  endif
  if (exists('kbytes') && kbytes >= 1000)
    let mbytes = kbytes / 1000
  endif

  if bytes <= 0
    return '0B'
  endif

  if (exists('mbytes'))
    return mbytes . 'MB '
  elseif (exists('kbytes'))
    return kbytes . 'KB '
  else
    return bytes . 'B '
  endif
endfunction

" A function to clear the undo history
function! <SID>ForgetUndo()
    let old_undolevels = &undolevels
    set undolevels=-1
    exe "normal a \<BS>\<Esc>"
    let &undolevels = old_undolevels
    unlet old_undolevels
endfunction
command -nargs=0 ClearUndo call <SID>ForgetUndo()

function! VisualSelection()
    if mode()=="v"
        let [line_start, column_start] = getpos("v")[1:2]
        let [line_end, column_end] = getpos(".")[1:2]
    else
        let [line_start, column_start] = getpos("'<")[1:2]
        let [line_end, column_end] = getpos("'>")[1:2]
    end
    if (line2byte(line_start)+column_start) > (line2byte(line_end)+column_end)
        let [line_start, column_start, line_end, column_end] =
        \   [line_end, column_end, line_start, column_start]
    end
    let lines = getline(line_start, line_end)
    if len(lines) == 0
            return ''
    endif
    let lines[-1] = lines[-1][: column_end - 1]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction

function! UnicodeEscapeString(str)
  let oldenc = &encoding
  set encoding=utf-8
  let escaped = substitute(a:str, '.', '\=printf("\\u%04x", char2nr(submatch(0)))', 'g')
  let &encoding = oldenc
  return escaped
endfunction

function! UnicodeUnescapeString(str)
  let oldenc = &encoding
  set encoding=utf-8
  let escaped = substitute(a:str, '\\u\([0-9a-fA-F]\{4\}\)', '\=nr2char("0x" . submatch(1))', 'g')
  let &encoding = oldenc
  return escaped
endfunction

function! ReplaceSelect(fn)
	" Preserve line breaks
	let l:paste = &paste
	set paste
	" Reselect the visual mode text
	normal! gv
	" Apply transformation to the text
	execute "normal! c\<c-r>=" . a:fn . "(@\")\<cr>\<esc>"
	" Select the new text
	normal! `[v`]h
	" Revert to previous mode
	let &paste = l:paste
endfunction

function! CDTerminalToCWD()
    call TerminalSend("cd '" . getcwd() . "'")
    call TerminalSend("\r")
endfunction
