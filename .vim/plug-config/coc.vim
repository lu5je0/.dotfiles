inoremap <silent><expr> <cr> pumvisible() ? coc#_select_confirm() : 
                                           \"\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

imap <expr> <tab> pumvisible() ?  "\<C-y>" : "\<TAB>"

let g:coc_snippet_next = '<cr>'

" Use <C-k> for jump to previous placeholder, it's default of coc.nvim
let g:coc_snippet_prev = '<c-g>'

" GoTo code navigation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gn <Plug>(coc-implementation)
nmap <silent> gu <Plug>(coc-type-definition)
" nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)
nmap <silent> K :call <SID>show_documentation()<CR>

" Use K to show documentation in preview window.
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

" Highlight the symbol and its references when holding the cursor.
augroup coc_hold
    autocmd!
    autocmd CursorHold * silent call CocActionAsync('highlight')
    autocmd ColorScheme * highlight CocHighlightText ctermbg=green guibg=#344134
augroup END

" Applying codeAction to the selected region.
" Example: `<leader>aap` for current paragraph
xmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>
nmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>

let g:coc_global_extensions = ['coc-json', 'coc-pyright', 'coc-snippets', 'coc-sql', 'coc-clangd']

inoremap <m-p> <C-\><C-O>:call CocActionAsync('showSignatureHelp')<cr>
inoremap <silent><expr> <c-n> coc#refresh()

" Use `[g` and `]g` to navigate diagnostics
" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)
