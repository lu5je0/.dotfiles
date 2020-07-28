" 按键映射 {{{
let mapleader=","

" vimrc
nnoremap <leader>vim :tabnew $MYVIMRC<cr>
nnoremap <leader>sou :source $MYVIMRC<cr>

" tab switch
map <leader>tn :tabnew<cr>
nnoremap <silent> <leader>th :tabprev<cr>
nnoremap <silent> <leader>tl :tabnext<cr>
nnoremap <silent> <leader>e :NERDTreeToggle<CR>
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

map <silent> <F10> :set wrap!<CR>
imap <silent> <F10> <ESC>:set wrap!<CR>

" 快速切换窗口
" normal
nmap <silent> <M-J> <C-w>j
nmap <silent> <M-K> <C-w>k
nmap <silent> <M-H> <C-w>h
nmap <silent> <M-L> <C-w>l

nmap <silent> <D-J> <C-w>j
nmap <silent> <D-K> <C-w>k
nmap <silent> <D-H> <C-w>h
nmap <silent> <D-L> <C-w>l

" ins<silent>ert
imap <silent> <M-J> <ESC><C-w>j
imap <silent> <M-K> <ESC><C-w>k
imap <silent> <M-H> <ESC><C-w>h
imap <silent> <M-L> <ESC><C-w>l

imap <silent> <D-J> <ESC><C-w>j
imap <silent> <D-K> <ESC><C-w>k
imap <silent> <D-H> <ESC><C-w>h
imap <silent> <D-L> <ESC><C-w>l

" ter<silent>minal
tmap <silent> <D-J> <C-w>j
tmap <silent> <D-K> <C-w>k
tmap <silent> <D-H> <C-w>h
tmap <silent> <D-L> <C-w>l
" }}}

" terminal-toggle {{{
" map <m-=> to toggle

" windows
tnoremap <silent> <m-=> <C-w>:ToggleTerminal<CR>
nnoremap <silent> <m-=> :ToggleTerminal<CR>
inoremap <silent> <m-=> <ESC>:ToggleTerminal<CR>

" mac
tnoremap <silent> <d-k> <C-w>:ToggleTerminal<CR>
nnoremap <silent> <d-k> :ToggleTerminal<CR>
inoremap <silent> <d-k> <ESC>:ToggleTerminal<CR>

" vim-translator {{{
" Echo translation in the cmdline
nmap <silent> <Leader>w <Plug>Translate
vmap <silent> <Leader>w <Plug>TranslateV
" Display translation in a window
nmap <silent> <Leader>s <Plug>TranslateW
vmap <silent> <Leader>s <Plug>TranslateWV
nmap <silent> <m-s> <Plug>TranslateW
vmap <silent> <m-s> <Plug>TranslateWV
" Replace the text with translation
" nmap <silent> <Leader>r <Plug>TranslateR
" vmap <silent> <Leader>r <Plug>TranslateRV
" }}}
