augroup file_type
    autocmd!
    autocmd FileType * set formatoptions-=o | if getfsize(@%) > 1024 * 1024 | echon "Disable syntax on large file" | setlocal syntax=OFF | endif
augroup END

augroup quick_list_preview
    autocmd!
    autocmd FileType qf nnoremap <buffer> p <CR><C-W>p
augroup END

augroup highlight_on_yank
    autocmd!
    autocmd TextYankPost * silent! lua vim.highlight.on_yank{higroup="Visual", timeout=300}
augroup END

" augroup signcolumn_increase
"     autocmd!
"     autocmd User CocDiagnosticChange setlocal signcolumn=yes:2
" augroup END
