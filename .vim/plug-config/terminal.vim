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

let g:asyncrun_mode='term'
let g:asyncrun_save=1
