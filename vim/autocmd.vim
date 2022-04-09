augroup l_default_group
    autocmd!

    " keep cursor postion in file
    autocmd BufReadPost * if line("'\"") > 1 && &ft != "gitcommit" && line("'\"") <= line("$") | exe "normal! g'\"" | endif

    autocmd FileType qf nnoremap <buffer> p <CR><C-W>p

    " highlight yank
    autocmd TextYankPost * silent! lua vim.highlight.on_yank{higroup="Visual", timeout=300}
augroup END
