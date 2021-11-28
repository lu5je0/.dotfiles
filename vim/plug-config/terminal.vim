" let g:terminal_pos='vertical'
" let g:terminal_fixheight=1
let g:terminal_height=18
" let g:terminal_pos='rightbelow'

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

" set your favorite shell
if has("win32")
    let g:toggle_terminal#command = 'wsl'
else
    let g:toggle_terminal#command = ''
endif

" terminal-toggle
nmap <silent> <m-i> :call TerminalToggle()<CR>
nmap <silent> <d-i> :call TerminalToggle()<CR>

imap <silent> <m-i> <ESC>:call TerminalToggle()<CR>
imap <silent> <d-i> <ESC>:call TerminalToggle()<CR>

tmap <silent> <m-i> <c-\><c-n>:call TerminalToggle()<CR>
tmap <silent> <d-i> <c-\><c-n>:call TerminalToggle()<CR>

" set your favorite shell
if has("win32")
    let g:toggle_terminal#command = 'wsl'
else
    let g:toggle_terminal#command = ''
endif
