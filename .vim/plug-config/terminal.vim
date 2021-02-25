let g:terminal_height=18
tmap <S-Insert> <C-W>"+


augroup term_nobufflisted
    autocmd!
    if !has("nvim")
        autocmd TerminalOpen * call s:TerminalOpen()
    else
        autocmd TermOpen * call s:TerminalOpen()
    endif
augroup END

fun! s:TerminalOpen()
    set nobuflisted
    nmap <buffer><silent> <c-i> <Nop>
    nmap <buffer><silent> <c-o> <Nop>
endf

" 设置wsl为默认shell
" if has("win32")
"     set shell=C:\Windows\WinSxS\amd64_microsoft-windows-lxss-wsl_31bf3856ad364e35_10.0.19041.423_none_60fa68722da1e84e\wsl.exe
"     set shellpipe=|
"     set shellredir=>
"     set shellcmdflag=
" endif

let g:asyncrun_mode='term'
let g:asyncrun_save=1
