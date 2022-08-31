let mapleader=","
let g:terminal_key='<c-_>'

" ctrl-c 复制
vnoremap <C-c> y

" 缩进后重新选择
xmap < <gv
xmap > >gv

nnoremap go o0<C-D>
nnoremap gO O0<C-D>

xnoremap gp p<Cmd>let @+ = @0<CR><Cmd>let @" = @0<CR>

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
nmap <PageUp>   :bprevious<CR>
nmap <PageDown> :bnext<CR>

"----------------------------------------------------------------------
" <leader>
"----------------------------------------------------------------------
nmap <silent> <leader>tN :tabnew<cr>

"----------------------------------------------------------------------
" window control
"----------------------------------------------------------------------
" 快速切换窗口
nmap <silent> <C-J> <C-w>j
nmap <silent> <C-K> <C-w>k
nmap <silent> <C-H> <C-w>h
nmap <silent> <C-L> <C-w>l

nmap <silent> <left> :bp<cr>
nmap <silent> <right> :bn<cr>
nmap <silent> <c-b>o <c-w>p
nmap <silent> <c-b><c-o> <c-w>p
nmap Q <cmd>execute 'normal @' .. reg_recorded()<CR>

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
xnoremap il $o^oh

onoremap ie :<c-u>normal! vgg0oG$<cr>
xnoremap ie gg0oG$

onoremap ae :<c-u>normal! vgg0oG$<cr>
xnoremap ae gg0oG$

"----------------------------------------------------------------------
" visual mode
"----------------------------------------------------------------------
xmap <silent> # :lua require("ext.terminal").run_select_in_terminal()<cr>

xmap <leader>cnc <plug>(ConvertToCamelword)
nmap <leader>cnc <plug>(ConvertToCamelword)
nmap <leader>cnC <plug>(ConvertToCamelWORD)

xmap <leader>cns <plug>(ConvertToSnakeword)
nmap <leader>cns <plug>(ConvertToSnakeword)
nmap <leader>cnS <plug>(ConvertToSnakeWORD)

xmap <leader>cnk <plug>(ConvertToKebabword)
nmap <leader>cnk <plug>(ConvertToKebabword)
nmap <leader>cnK <plug>(ConvertToKebabWORD)

xmap <leader>cnp <plug>(ConvertToPascalword)
nmap <leader>cnp <plug>(ConvertToPascalword)
nmap <leader>cnP <plug>(ConvertToPascalWORD)

"----------------------------------------------------------------------
" wrap
"----------------------------------------------------------------------
function! ToggleGj(echo)
    if !exists("g:ToggleGj")
        let g:ToggleGj = 0
    endif
    if g:ToggleGj == 1
        xmap j gj
        xmap k gk
        nmap j gj
        nmap k gk
        nmap H g^
        nmap L g$
        xmap H g^
        xmap L g$
        omap H g^
        omap L g$
        nmap Y gyg$
        if a:echo
            echo "gj on"
        endif
        let g:ToggleGj = 0
    else
        silent! unmap j
        silent! unmap k
        nmap H ^
        nmap L $
        xmap H ^
        xmap L $
        omap H ^
        omap L $
        nmap Y y$
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
xnoremap * m`:keepjumps <C-u>call visual#star_search_set('/')<CR>/<C-R>=@/<CR><CR>``
nnoremap v m'v
nnoremap V m'V

"----------------------------------------------------------------------
" leader
"----------------------------------------------------------------------
nmap <leader>q <cmd>lua require("lu5je0.misc.quit-prompt").close_buffer()<cr>
nmap <leader>Q <cmd>lua require("lu5je0.misc.quit-prompt").exit()<cr>
nmap <leader>% :%s/

nmap <leader>wo <c-w>o

" Echo translation in the cmdline
nmap <silent> <Leader>sc <Plug>Translate
xmap <silent> <Leader>sc <Plug>TranslateV

" say it
nmap <silent> <Leader>sa :call misc#say_it()<cr><Plug>TranslateW
xmap <silent> <Leader>sa :call misc#visual_say_it()<cr><Plug>TranslateWV

" xmap <silent> <Leader>sc <Plug>TranslateV
" Display translation in a window
nmap <silent> <Leader>ss <Plug>TranslateW
xmap <silent> <Leader>ss <Plug>TranslateWV
" Replace the text with translation
nmap <silent> <Leader>sr <Plug>TranslateR
xmap <silent> <Leader>sr <Plug>TranslateRV

"----------------------------------------------------------------------
" 繁体简体
"----------------------------------------------------------------------
xmap <leader>xz :!opencc -c t2s<cr>
nmap <leader>xz :%!opencc -c t2s<cr>
xmap <leader>xZ :!opencc -c s2t<cr>
nmap <leader>xZ :%!opencc -c s2t<cr>


"----------------------------------------------------------------------
" base64
"----------------------------------------------------------------------
xmap <silent> <leader>xB :<c-u>call base64#v_atob()<cr>
xmap <silent> <leader>xb :<c-u>call base64#v_btoa()<cr>


"----------------------------------------------------------------------
" unicode escape
"----------------------------------------------------------------------
xmap <silent> <leader>xu :<c-u>call visual#replace_by_fn("UnicodeEscapeString")<cr>
xmap <silent> <leader>xU :<c-u>call visual#replace_by_fn("UnicodeUnescapeString")<cr>

"----------------------------------------------------------------------
" text escape
"----------------------------------------------------------------------
xmap <silent> <leader>xs :<c-u>call visual#replace_by_fn("EscapeText")<cr>
" xmap <silent> <leader>xU :<c-u>call visual#replace_by_fn("UnicodeUnescapeString")<cr>

"----------------------------------------------------------------------
" url encode
"----------------------------------------------------------------------
nmap <leader>xh :%!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
nmap <leader>xH :%!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>

xmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>
nmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>

xmap <leader>xh :!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
xmap <leader>xH :!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>

" ugly hack to start newline and keep indent
nnoremap <silent> o o<space><bs>
nnoremap <silent> O O<space><bs>
inoremap <silent> <cr> <cr><space><bs>

" augroup AutoReIndentAfterPaste
"     autocmd!
"     autocmd FileType vim,lua,python nmap <buffer> <silent> <expr> p v:lua.require('lu5je0.core.register').is_register_contains_newline('"') ? 'p`[V`]=^' : 'p'
" augroup END

"----------------------------------------------------------------------
" command line map
"----------------------------------------------------------------------
cmap <c-a> <c-b>
