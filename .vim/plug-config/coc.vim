imap <expr> <cr> pumvisible() ? "\<C-y>\<cr>" : "\<cr>"
imap <expr> <tab> pumvisible() ? "\<C-y>" : "\<Plug>snipMateNextOrTrigger"
imap <expr> . pumvisible() ? "\<C-y>." : "."
imap <c-j> <Plug>snipMateNextOrTrigger
imap <c-k> <Plug>snipMateBack

inoremap <silent><expr> <cr> pumvisible() ? coc#_select_confirm()
            \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
