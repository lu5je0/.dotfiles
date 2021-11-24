augroup file_type
    autocmd!
    autocmd FileType * set formatoptions-=o | if getfsize(@%) > 1024 * 1024 | echon "Disable syntax on large file" | setlocal syntax=OFF | endif
augroup END

augroup quick_list_preview
    autocmd!
    autocmd FileType qf nnoremap <buffer> p <CR><C-W>p
augroup END
