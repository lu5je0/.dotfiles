let g:coc_global_extensions = ['coc-json', 'coc-pyright', 'coc-snippets', 'coc-sql', 'coc-lua']

inoremap <silent><expr> <cr> pumvisible() ? "\<C-y>\<C-g>u" : 
                                           \"\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

imap <silent><expr> <tab> pumvisible() ?  "\<C-y>\<C-g>u" : "\<TAB>"

" Use <C-k> for jump to previous placeholder, it's default of coc.nvim
let g:coc_snippet_next = '<C-J>'
let g:coc_snippet_prev = '<C-k>'

augroup user_plugin_coc
    autocmd!
    " Highlight the symbol and its references when holding the cursor.
    " autocmd CursorHold * silent call CocActionAsync('highlight')
    autocmd ColorScheme * highlight CocHighlightText ctermbg=green guibg=#344134
    autocmd FileType go,python,cpp,java,js,c nmap <buffer> <silent> gd <Plug>(coc-definition)
augroup END

" GoTo code navigation.
nmap <silent> gn <Plug>(coc-implementation)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gb <Plug>(coc-references)

" Use K to show documentation in preview window.
nmap <silent> K :call <SID>show_documentation()<CR>
function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  elseif (coc#rpc#ready())
    call CocActionAsync('doHover')
  else
    execute '!' . &keywordprg . " " . expand('<cword>')
  endif
endfunction

" Symbol renaming.
nmap <leader>cr <Plug>(coc-rename)

xmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>
nmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>

inoremap <silent><m-p> <C-\><C-O>:call CocActionAsync('showSignatureHelp')<cr>
inoremap <silent><expr> <c-n> coc#refresh()

" Use `[g` and `]g` to navigate diagnostics
" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
nmap <silent> [e <Plug>(coc-diagnostic-prev)
nmap <silent> ]e <Plug>(coc-diagnostic-next)

" Remap <C-f> and <C-b> for scroll float windows/popups.
if has('nvim-0.4.0') || has('patch-8.2.0750')
  nnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
  nnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
  inoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(1)\<cr>" : "\<Right>"
  inoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(0)\<cr>" : "\<Left>"
  vnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
  vnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
endif
