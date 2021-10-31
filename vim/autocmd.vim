augroup file_type
    autocmd!
    autocmd FileType * set formatoptions-=o | if getfsize(@%) > 1024 * 1024 | echon "Disable syntax on large file" | setlocal syntax=OFF | endif
augroup END
