let mapleader=","
let g:terminal_key='<c-_>'

" ctrl-c 复制
vnoremap <C-c> y

" 缩进后重新选择
vmap < <gv
vmap > >gv

nmap H ^
nmap L $
vmap H ^
vmap L $
omap H ^
omap L $

nmap Y ^y$

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
nmap <silent> <C-J> <C-w>j
nmap <silent> <C-K> <C-w>k
nmap <silent> <C-H> <C-w>h
nmap <silent> <C-L> <C-w>l

" terminal-toggle
nmap <silent> <M-i> :call TerminalToggle()<CR>
nmap <silent> <D-i> :call TerminalToggle()<CR>
tmap <silent> <M-i> <c-\><c-n>:call TerminalToggle()<CR>
tmap <silent> <D-i> <c-\><c-n>:call TerminalToggle()<CR>


" alt command
" nmap <silent> <D-j> <C-w>j
" nmap <silent> <D-k> <C-w>k
" nmap <silent> <D-h> <C-w>h
" nmap <silent> <D-l> <C-w>l

" nmap <silent> <M-j> <C-w>j
" nmap <silent> <M-k> <C-w>k
" nmap <silent> <M-h> <C-w>h
" nmap <silent> <M-l> <C-w>l

" tmap <silent> <D-j> <C-w>j
" tmap <silent> <D-k> <C-w>k
" tmap <silent> <D-h> <C-w>h
" tmap <silent> <D-l> <C-w>l

" nvim todo

" popup
nmap <Leader>s <Plug>(coc-translator-p)
vmap <Leader>s <Plug>(coc-translator-pv)

" visual-multi
map <c-d-n> <Plug>(VM-Add-Cursor-Down)
map <c-d-p> <Plug>(VM-Add-Cursor-Up)
map <c-m-n> <Plug>(VM-Add-Cursor-Down)
map <c-m-p> <Plug>(VM-Add-Cursor-Up)

nmap <F2> :bp<cr>
nmap <F3> :bn<cr>
nnoremap <PageUp>   :bprevious<CR>
nnoremap <PageDown> :bnext<CR>

nmap <Leader>1 <Plug>lightline#bufferline#go(1)
nmap <Leader>2 <Plug>lightline#bufferline#go(2)
nmap <Leader>3 <Plug>lightline#bufferline#go(3)
nmap <Leader>4 <Plug>lightline#bufferline#go(4)
nmap <Leader>5 <Plug>lightline#bufferline#go(5)
nmap <Leader>6 <Plug>lightline#bufferline#go(6)
nmap <Leader>7 <Plug>lightline#bufferline#go(7)
nmap <Leader>8 <Plug>lightline#bufferline#go(8)
nmap <Leader>9 <Plug>lightline#bufferline#go(9)
nmap <Leader>0 <Plug>lightline#bufferline#go(10)
nmap <silent> <leader>Q :call QuitForce()<CR>
nmap Q <Nop>

" let s:python = executable('python3')? 'python3' : 'python'
if has("win32")
    nmap <leader>rr :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python "$(VIM_FILEPATH)"<CR>
else
    nmap <leader>rr :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python3 "$(VIM_FILEPATH)"<CR>
endif

fun SplitWithBuffer(n)
    let l:buffer_number = lightline#bufferline#get_buffer_for_ordinal_number(a:n)
    execute "vertical sb" l:buffer_number
endf

map <leader>w1 :call SplitWithBuffer(1)<cr>
map <leader>w2 :call SplitWithBuffer(2)<cr>
map <leader>w3 :call SplitWithBuffer(3)<cr>
map <leader>w4 :call SplitWithBuffer(4)<cr>
map <leader>w5 :call SplitWithBuffer(5)<cr>
map <leader>w6 :call SplitWithBuffer(6)<cr>
map <leader>w7 :call SplitWithBuffer(7)<cr>
map <leader>w8 :call SplitWithBuffer(8)<cr>
map <leader>w9 :call SplitWithBuffer(9)<cr>

command! -nargs=1 SplitWithBuffer call SplitWithBuffer(<f-args>)

" undotree esc映射
function g:Undotree_CustomMap()
    nmap <buffer> <ESC> <plug>UndotreeClose
endfunc
