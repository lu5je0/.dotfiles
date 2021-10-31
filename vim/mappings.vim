let mapleader=","
let g:terminal_key='<c-_>'

" ctrl-c 复制
vnoremap <C-c> y

" 缩进后重新选择
vmap < <gv
vmap > >gv

map <silent><expr> j &wrap ? "gj" : "j"
map <silent><expr> k &wrap ? "gk" : "k"

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
nmap <silent> <m-i> :call TerminalToggle()<CR>
nmap <silent> <d-i> :call TerminalToggle()<CR>

imap <silent> <m-i> <ESC>:call TerminalToggle()<CR>
imap <silent> <d-i> <ESC>:call TerminalToggle()<CR>

tmap <silent> <m-i> <c-\><c-n>:call TerminalToggle()<CR>
tmap <silent> <d-i> <c-\><c-n>:call TerminalToggle()<CR>

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

nmap <silent> <left> :bp<cr>
nmap <silent> <right> :bn<cr>
nmap <silent> <leader>Q :call QuitForce()<CR>
nmap Q <Nop>

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

onoremap ie :<c-u>normal! vgg0oG$<cr>
vnoremap ie gg0oG$

onoremap ae :<c-u>normal! vgg0oG$<cr>
vnoremap ae gg0oG$

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
vmap <silent> # :call visual#runSelectInTerminal()<cr>
