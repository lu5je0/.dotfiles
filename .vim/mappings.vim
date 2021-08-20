let mapleader=","
let g:terminal_key='<c-_>'

" ctrl-c 复制
vnoremap <C-c> y

" 缩进后重新选择
vmap < <gv
vmap > >gv

nmap <silent><expr> j &wrap ? "gj" : "j"
nmap <silent><expr> k &wrap ? "gk" : "k"
vmap <silent><expr> j &wrap ? "gj" : "j"
vmap <silent><expr> k &wrap ? "gk" : "k"

nmap <silent><expr> H &wrap ? "g^" : "^"
nmap <silent><expr> L &wrap ? "g$" : "$"
vmap <silent><expr> H &wrap ? "g^" : "^"
vmap <silent><expr> L &wrap ? "g$" : "$"
omap <silent><expr> H &wrap ? "g^" : "^"
omap <silent><expr> L &wrap ? "g$" : "$"
nmap <silent><expr> Y &wrap ? "g^yg$" : "^y$"

nnoremap go }o<Esc>o
nnoremap gO {O<Esc>O

imap <M-j> <down>
imap <M-k> <up>
imap <M-h> <left>
imap <M-l> <right>

map <silent> <m-cr> <leader>cc
imap <silent> <m-cr> <leader>cc
map <silent> <d-cr> <leader>cc
imap <silent> <d-cr> <leader>cc

" 另存为
if has("gui_running")
    map <silent> <C-S> :brow saveas<CR>
    imap <silent> <C-S> <ESC>:brow saveas<CR>a
endif

" terminal-toggle
nmap <silent> <M-i> :call TerminalToggle()<CR>
nmap <silent> <D-i> :call TerminalToggle()<CR>

imap <silent> <M-i> <ESC>:call TerminalToggle()<CR>
imap <silent> <D-i> <ESC>:call TerminalToggle()<CR>

tmap <silent> <M-i> <c-\><c-n>:call TerminalToggle()<CR>
tmap <silent> <D-i> <c-\><c-n>:call TerminalToggle()<CR>

" visual-multi
map <c-d-n> <Plug>(VM-Add-Cursor-Down)
map <c-d-p> <Plug>(VM-Add-Cursor-Up)
map <c-m-n> <Plug>(VM-Add-Cursor-Down)
map <c-m-p> <Plug>(VM-Add-Cursor-Up)

nmap <F2> :bp<cr>
nmap <F3> :bn<cr>
nnoremap <PageUp>   :bprevious<CR>
nnoremap <PageDown> :bnext<CR>

"----------------------------------------------------------------------
" window control
"----------------------------------------------------------------------
noremap <silent><space>= :resize +3<cr>
noremap <silent><space>- :resize -3<cr>
noremap <silent><space>, :vertical resize -3<cr>
noremap <silent><space>. :vertical resize +3<cr>

" 快速切换窗口
nmap <silent> <C-J> <C-w>j
nmap <silent> <C-K> <C-w>k
nmap <silent> <C-H> <C-w>h
nmap <silent> <C-L> <C-w>l

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
nmap <silent> <left> :bp<cr>
nmap <silent> <right> :bn<cr>
nmap <silent> <leader>Q :call QuitForce()<CR>
nmap Q <Nop>

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

" 打断undo
inoremap . <c-g>u.

"----------------------------------------------------------------------
" text-objects
"----------------------------------------------------------------------
onoremap il :<c-u>normal! v$o^oh<cr>
vnoremap il $o^oh

xnoremap <silent> ij i"
onoremap <silent> ij :normal vij<CR>

xnoremap <silent> aj a"
onoremap <silent> aj :normal vaj<CR>

" let s:python = executable('python3')? 'python3' : 'python'
if has("win32")
    nmap <leader>rr :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python "$(VIM_FILEPATH)"<CR>
else
    nmap <leader>rr :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python3 "$(VIM_FILEPATH)"<CR>
endif

" git next hunk
nmap ]g <plug>(signify-next-hunk)
nmap [g <plug>(signify-prev-hunk)

"----------------------------------------------------------------------
" visual mode
"----------------------------------------------------------------------
vmap <silent> t :call visual#runSelectInTerminal()<cr>
