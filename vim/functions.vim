function! SynStack()
    for i1 in synstack(line("."), col("."))
        let i2 = synIDtrans(i1)
        let n1 = synIDattr(i1, "name")
        let n2 = synIDattr(i2, "name")
        echo n1 "->" n2
    endfor
endfunction

" Toggle signcolumn. Works on vim>=8.1 or NeoVim
function! ToggleSignColumn()
    if &signcolumn == 'yes:1'
        set signcolumn=no
        echo "signcolumn=no"
    else
        set signcolumn=yes:1
        echo "signcolumn=yes:1"
    endif
endfunction

" Toggles foldcolumn
function! s:ToggleFoldColumn()
    if &foldcolumn == 'auto:9'
        set foldcolumn=0
    else
        set foldcolumn=auto:9
    endif
endfunction
nnoremap <silent> <Plug>FoldToggleColumn :call <SID>ToggleFoldColumn()<CR>

function! VisualStarSearchSet(cmdtype,...)
  let temp = @"
  normal! gvy
  if !a:0 || a:1 != 'raw'
    let @" = escape(@", a:cmdtype.'\*')
  endif
  let @/ = substitute(@", '\n', '\\n', 'g')
  let @/ = substitute(@/, '\[', '\\[', 'g')
  let @/ = substitute(@/, '\~', '\\~', 'g')
  let @/ = substitute(@/, '\.', '\\.', 'g')
  let @" = temp
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
    set paste!
endfunction

function! IsVisualMode()
    if mode() == "v"
        return "'<,'>"
    else
        return ""
    endif
endfunction

function! ToggleWrap()
    set wrap!
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
import lang_detector
import importlib
importlib.reload(functions)
EOF
let g:py_func_init = 1
endfunction

function! GuessLang(...)
call PyFuncInit()
python3 << EOF
lang_detector.detect_filetype()
EOF
endfunction
command! -nargs=* GuessLang call GuessLang(<f-args>)

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
    return mbytes . 'MB'
  elseif (exists('kbytes'))
    return kbytes . 'KB'
  else
    return bytes . 'B'
  endif
endfunction

function! CurVimPath()
    let name = getcwd()
    return fnamemodify(name, ':p:h:t')
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

function! EscapeText(text)
    let l:escaped_text = a:text
    " Map characters to named C backslash escapes. Normally, single-quoted
    " strings don't require double-backslashing, but these are necessary
    " to make the substitute() call below work properly.

    " \   "'"     : '\\''',
    let l:charmap = {
    \   '"'     : '\\"',
    \   "\n"    : '\\n',
    \   "\r"    : '\\r',
    \   "\b"    : '\\b',
    \   "\t"    : '\\t',
    \   "\x07"  : '\\a',
    \   "\x0B"  : '\\v',
    \   "\f"    : '\\f',
    \   }

    " Escape any existing backslashes in the text first, before
    " generating new ones. (Vim dictionaries iterate in arbitrary order,
    " so this step can't be combined with the items() loop below.)
    "
    let l:escaped_text = substitute(l:escaped_text, "\\", '\\\', 'g')

    " Replace actual returns, newlines, tabs, etc., with their escaped
    " representations.
    "
    for [original, escaped] in items(charmap)
        let l:escaped_text = substitute(l:escaped_text, original, escaped, 'g')
    endfor

    " Replace any other character that isn't a letter, number,
    " punctuation, or space with a 3-digit octal escape sequence. (Octal
    " is used instead of hex, since octal escapes terminate after 3
    " digits. C allows hex escapes of any length, so it's possible for
    " them to run up against subsequent characters that might be valid
    " hex digits.)
    "
    let l:escaped_text = substitute(l:escaped_text,
    \   '\([^[:alnum:][:punct:] ]\)',
    \   '\="\\o" . printf("%03o",char2nr(submatch(1)))',
    \   'g')

    return l:escaped_text
endfunction
