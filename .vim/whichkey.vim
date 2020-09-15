let g:mapleader = "\<Space>"
let g:maplocalleader = ','
nnoremap <silent> <leader>      :<c-u>WhichKey '<Space>'<CR>
nnoremap <silent> <localleader> :<c-u>WhichKey  ','<CR>
let g:which_key_map = {}

" vim toggle
let g:which_key_map.v = {
      \ 'name' : '+vim toggle' ,
      \ 'j' : [':call ToggleGj()', 'Toggle gj'],
      \ 'v' : [':tabnew $MYVIMRC | :cd ' . $HOME . '/.dotfiles', 'vimrc'],
      \ 's' : [':source ' .  $MYVIMRC, 'apply vimrc'],
      \ 'w' : [':set wrap!', 'set wrap'],
      \ }

" leaderf
let g:which_key_map.f = {
      \ 'name' : '+Leaderf' ,
      \ 'f' : [':Leaderf file', 'file'],
      \ 'b' : [':Leaderf buffer', 'buffer'],
      \ 'm' : [':Leaderf mru', 'mru'],
      \ 'l' : [':Leaderf line', 'line'],
      \ 'n' : [':Leaderf filetype', 'filetype'],
      \ }

call which_key#register(',', "g:which_key_map")
