let mapleader=","
let g:terminal_key='<c-_>'

" ctrl-c 复制
vnoremap <C-c> y

" 缩进后重新选择
vmap < <gv
vmap > >gv

nnoremap go o0<C-D>
nnoremap gO O0<C-D>

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
nmap <silent> <c-b>o <c-w>p
nmap <silent> <c-b><c-o> <c-w>p
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

sunmap ae
sunmap ie
sunmap il

"----------------------------------------------------------------------
" visual mode
"----------------------------------------------------------------------
vmap <silent> # :lua require("core.terminal").run_select_in_terminal()<cr>

vmap <leader>xnc <plug>(ConvertToCamelWord)
nmap <leader>xnc <plug>(ConvertToCamelWord)
nmap <leader>xnC <plug>(ConvertToCamelWORD)

vmap <leader>xns <plug>(ConvertToSnakeWord)
nmap <leader>xns <plug>(ConvertToSnakeWord)
nmap <leader>xnS <plug>(ConvertToSnakeWORD)

vmap <leader>xnk <plug>(ConvertToKababWord)
nmap <leader>xnk <plug>(ConvertToKababWord)
nmap <leader>xnK <plug>(ConvertToKababWORD)

vmap <leader>xnp <plug>(ConvertToPascalWord)
nmap <leader>xnp <plug>(ConvertToPascalWord)
nmap <leader>xnP <plug>(ConvertToPascalWORD)

"----------------------------------------------------------------------
" wrap
"----------------------------------------------------------------------
function! ToggleGj(echo)
    if !exists("g:ToggleGj")
        let g:ToggleGj = 0
    endif
    if g:ToggleGj == 1
        vmap j gj
        vmap k gk
        nmap j gj
        nmap k gk
        nmap H g^
        nmap L g$
        vmap H g^
        vmap L g$
        omap H g^
        omap L g$
        nmap Y g^yg$
        if a:echo
            echo "gj on"
        endif
        let g:ToggleGj = 0
    else
        silent! unmap j
        silent! unmap k
        nmap H ^
        nmap L $
        vmap H ^
        vmap L $
        omap H ^
        omap L $
        nmap Y ^y$
        if a:echo
            echo "gj off"
        endif
        let g:ToggleGj = 1
    endif
endfunction
call ToggleGj(0)

"----------------------------------------------------------------------
" other
"----------------------------------------------------------------------
nnoremap * m`:keepjumps normal! *``<cr>
xnoremap * m`:keepjumps <C-u>call VisualStarSearchSet('/')<CR>/<C-R>=@/<CR><CR>``

"----------------------------------------------------------------------
" leader
"----------------------------------------------------------------------
nmap <leader>q <cmd>CloseBuffer<cr>
nmap <leader>Q <cmd>lua require("base.quit-comfirm").exit()<cr>

nmap <leader>cf <cmd>lua vim.lsp.buf.formatting()<CR>
vmap <leader>cf <cmd>lua vim.lsp.buf.range_formatting()<CR>

" ugly hack to start newline and keep indent
" nnoremap o o<space><BS>
" nnoremap O O<space><BS>

" augroup AutoReIndentAfterPaste
"     autocmd!
"     autocmd FileType vim,lua,python nmap <buffer> <silent> <expr> p v:lua.require('utils.register-utils').is_register_contains_newline('"') ? 'p`[V`]=^' : 'p'
" augroup END
