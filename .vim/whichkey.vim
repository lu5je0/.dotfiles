set timeoutlen=500

let g:mapleader = "\<Space>"
let g:maplocalleader = ','
nnoremap <silent> <leader>      :<c-u>WhichKey '<Space>'<CR>
nnoremap <silent> <localleader> :<c-u>WhichKey  ','<CR>
let g:which_key_map = {}

" hide 1-9
let g:which_key_map.1 = 'which_key_ignore'
let g:which_key_map.2 = 'which_key_ignore'
let g:which_key_map.3 = 'which_key_ignore'
let g:which_key_map.4 = 'which_key_ignore'
let g:which_key_map.5 = 'which_key_ignore'
let g:which_key_map.6 = 'which_key_ignore'
let g:which_key_map.7 = 'which_key_ignore'
let g:which_key_map.8 = 'which_key_ignore'
let g:which_key_map.9 = 'which_key_ignore'

" undo tree
let g:which_key_map.r = [':UndotreeToggle', 'undotree']
let g:which_key_map.e = [':NERDTreeToggle', 'nerd']

" vim toggle
let g:which_key_map.v = {
      \ 'name' : '+vim toggle' ,
      \ 'j' : [':call ToggleGj()', 'toggle gj'],
      \ 'v' : [':tabnew $MYVIMRC | :cd ' . $HOME . '/.dotfiles', 'open vimrc'],
      \ 's' : [':source ' .  $MYVIMRC, 'apply vimrc'],
      \ 'n' : [':set invnumber', 'toggle number'],
      \ 'w' : [':set wrap!', 'toggle wrap'],
      \ }

" +tab or terminal
let g:which_key_map.t = {
      \ 'name' : '+tab or terminal' ,
      \ 't' : [':ToggleTerminal', 'open terminal'],
      \ 'n' : [':tabnew', 'new tab'],
      \ }

" code
let g:which_key_map.C = {
      \ 'name' : '+Code' ,
      \ 'u' : [':set ff=unix', 'unix'],
      \ 'd' : [':set ff=dos', 'dos'],
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
