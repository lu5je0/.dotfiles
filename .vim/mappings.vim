let mapleader=","
let g:terminal_key='<c-_>'

" tab switch
nnoremap <silent> <leader>1 1gt
nnoremap <silent> <leader>2 2gt
nnoremap <silent> <leader>3 3gt
nnoremap <silent> <leader>4 4gt
nnoremap <silent> <leader>5 5gt
nnoremap <silent> <leader>6 6gt
nnoremap <silent> <leader>7 7gt
nnoremap <silent> <leader>8 8gt
nnoremap <silent> <leader>9 9gt

if has("win32")
    " 为了支持win+v
    imap <C-v> <ESC>"+gpa
    nmap <C-v> "+gpa
endif

" ctrl-c 复制
vnoremap <C-c> y

" 缩进后重新选择
vmap < <gv
vmap > >gv

imap <M-j> <down>
imap <M-k> <up>
imap <M-h> <left>
imap <M-l> <right>

" 另存为
if has("gui_running")
    map <silent> <C-S> :brow saveas<CR>
    imap <silent> <C-S> <ESC>:brow saveas<CR>a
endif

" 快速切换窗口
" normal
nmap <silent> <C-J> <C-w>j
nmap <silent> <C-K> <C-w>k
nmap <silent> <C-H> <C-w>h
nmap <silent> <C-L> <C-w>l

tmap <silent> <C-J> <C-w>j
tmap <silent> <C-K> <C-w>k
tmap <silent> <C-H> <C-w>h
tmap <silent> <C-L> <C-w>l


" alt command
nmap <silent> <D-j> <C-w>j
nmap <silent> <D-k> <C-w>k
nmap <silent> <D-h> <C-w>h
nmap <silent> <D-l> <C-w>l

nmap <silent> <M-j> <C-w>j
nmap <silent> <M-k> <C-w>k
nmap <silent> <M-h> <C-w>h
nmap <silent> <M-l> <C-w>l

tmap <silent> <D-j> <C-w>j
tmap <silent> <D-k> <C-w>k
tmap <silent> <D-h> <C-w>h
tmap <silent> <D-l> <C-w>l

" nvim todo

" vim-translator
nmap <silent> <Leader>s <Plug>TranslateW
vmap <silent> <Leader>s <Plug>TranslateWV
nmap <silent> <m-s> <Plug>TranslateW
vmap <silent> <m-s> <Plug>TranslateWV

nmap H ^
nmap L $
vmap H ^
vmap L $
omap H ^
omap L $

nmap <M-i> :call TerminalToggle()<CR>
nmap <D-i> :call TerminalToggle()<CR>
tmap <M-i> <c-\><c-n>:call TerminalToggle()<CR>
tmap <D-i> <c-\><c-n>:call TerminalToggle()<CR>

" visual-multi
map <d-n> <Plug>(VM-Add-Cursor-Down)
map <d-p>   <Plug>(VM-Add-Cursor-Up)
map <m-n> <Plug>(VM-Add-Cursor-Down)
map <m-p>   <Plug>(VM-Add-Cursor-Up)
