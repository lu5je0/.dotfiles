let g:terminal_height=18
tmap <S-Insert> <C-W>"+

if !has("nvim")
    autocmd TerminalOpen * set nobuflisted
else
    autocmd TermOpen * set nobuflisted
endif
" imap <F5> <ESC>:AsyncRun -mode=term -pos=bottom python "$(VIM_FILEPATH)"<CR>
if has("win32")
    nmap <F5> :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python "$(VIM_FILEPATH)"<CR>
else
    nmap <F5> :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python3 "$(VIM_FILEPATH)"<CR>
endif

let g:asyncrun_mode='term'
let g:asyncrun_save=1
" let g:asyncrun_status = ''
" let g:airline_section_error = airline#section#create_right(['%{g:asyncrun_status}'])
