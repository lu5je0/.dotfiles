vim.cmd[[
function! s:suppress_netrw() abort
  if exists('#FileExplorer')
    autocmd! FileExplorer *
  endif
endfunction

function! s:expand(expr) abort
  return expand(a:expr)
endfunction

function! s:hijack_directory() abort
  let path = s:expand('%:p')
  if !isdirectory(path)
    return
  endif
  PackerLoad nvim-tree.lua
  execute printf('NvimTreeOpen %s', fnameescape(path))
endfunction

augroup netrw-hijack
  autocmd!
  autocmd VimEnter * call s:suppress_netrw()
  autocmd BufEnter * call s:hijack_directory()
augroup END
]]
