let g:terminal_height=18
tmap <S-Insert> <C-W>"+

imap <F5> <ESC>:AsyncRun -mode=term -pos=thelp python "$(VIM_FILEPATH)"<CR>
nmap <F5> :AsyncRun -mode=term -pos=thelp python "$(VIM_FILEPATH)"<CR>
