let g:terminal_height=18
tmap <S-Insert> <C-W>"+

if !has("nvim")
    autocmd TerminalOpen * set nobuflisted
else
    autocmd TermOpen * set nobuflisted
endif

" 设置wsl为默认shell
" if has("win32")
"     set shell=C:\Windows\WinSxS\amd64_microsoft-windows-lxss-wsl_31bf3856ad364e35_10.0.19041.423_none_60fa68722da1e84e\wsl.exe
"     set shellpipe=|
"     set shellredir=>
"     set shellcmdflag=
" endif

if has("win32")
    nmap <F5> :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python "$(VIM_FILEPATH)"<CR>
else
    nmap <F5> :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python3 "$(VIM_FILEPATH)"<CR>
endif

let g:asyncrun_mode='term'
let g:asyncrun_save=1
