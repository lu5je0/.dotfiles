" How each level is indented and what to prepend.
" This could make the display more compact or more spacious.
" e.g., more compact: ["▸ ", ""]
" Note: this option only works for the kind renderer, not the tree renderer.
let g:vista_icon_indent = ["╰─▸ ", "├─▸ "]

" The default icons can't be suitable for all the filetypes, you can extend it as you wish.
let g:vista#renderer#icons = {
\   "function": "\uf794",
\   "variable": "",
\  }

" Set the executive for some filetypes explicitly. Use the explicit executive
" instead of the default one for these filetypes when using `:Vista` without
" specifying the executive.
let g:vista_executive_for = {
  \ 'python': 'coc',
  \ 'java': 'coc',
  \ 'vim': 'coc',
  \ }

function! s:vista_mapping() abort
  nmap <buffer> <leader>d <C-W>h<leader>d
  nmap <buffer> <leader>1 <C-W>h<leader>1
  nmap <buffer> <leader>2 <C-W>h<leader>2
  nmap <buffer> <leader>3 <C-W>h<leader>3
  nmap <buffer> <leader>4 <C-W>h<leader>4
  nmap <buffer> <leader>5 <C-W>h<leader>5
  nmap <buffer> <leader>6 <C-W>h<leader>6
  nmap <buffer> <leader>7 <C-W>h<leader>7
  nmap <buffer> <leader>8 <C-W>h<leader>8
  nmap <buffer> <leader>9 <C-W>h<leader>9
  nmap <buffer> <leader>ff <C-W>h<leader>ff
  nmap <buffer> <leader>fr <C-W>h<leader>fr
  nmap <buffer> <leader>fm <C-W>h<leader>fm
  nmap <buffer> <leader>fb <C-W>h<leader>fb
endfunction

augroup vista-mapping-group
  autocmd! *
  autocmd FileType vista,vista_kind call s:vista_mapping()
augroup END
