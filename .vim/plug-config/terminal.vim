let g:terminal_height=18
tmap <S-Insert> <C-W>"+

" imap <F5> <ESC>:AsyncRun -mode=term -pos=bottom python "$(VIM_FILEPATH)"<CR>
if has("win32")
    nmap <F5> :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python "$(VIM_FILEPATH)"<CR>
endif

let g:asyncrun_mode='term'
let g:asyncrun_save=1
