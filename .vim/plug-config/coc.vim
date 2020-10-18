imap <expr> <cr> pumvisible() ? "\<C-y>" : "\<cr>"

imap <expr> <tab> pumvisible() ?  "\<C-y>" : "\<TAB>"

imap <expr> . pumvisible() ? "\<C-y>." : "."

" Use <C-j> for jump to next placeholder, it's default of coc.nvim
let g:coc_snippet_next = '<c-j>'

" Use <C-k> for jump to previous placeholder, it's default of coc.nvim
let g:coc_snippet_prev = '<c-k>'

" GoTo code navigation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K to show documentation in preview window.
nnoremap <silent> K :call <SID>show_documentation()<CR>
function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  elseif (coc#rpc#ready())
    call CocActionAsync('doHover')
  else
    execute '!' . &keywordprg . " " . expand('<cword>')
  endif
endfunction

" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent call CocActionAsync('highlight')

" Symbol renaming.
nmap <leader>rn <Plug>(coc-rename)

" nmap <leader>rf <Plug>(coc-fix-current)
" command! -nargs=0 Format :call CocAction('format')

autocmd ColorScheme * highlight CocHighlightText ctermbg=green guibg=#344134

let g:coc_global_extensions = ['coc-json', 'coc-python', 'coc-highlight', 'coc-java']
