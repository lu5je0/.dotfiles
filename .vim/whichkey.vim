set timeoutlen=500

" Hide status line
autocmd! FileType which_key
autocmd  FileType which_key set laststatus=0 noshowmode noruler
\| autocmd BufLeave <buffer> set laststatus=2 noshowmode ruler

let g:which_key_use_floating_win = 0

" let g:mapleader = "\<Space>"
let g:maplocalleader = ','
" nnoremap <silent> <leader>      :<c-u>WhichKey '<Space>'<CR>
nnoremap <silent> <localleader> :<c-u>WhichKey  ','<CR>
vnoremap <silent> <localleader> :<c-u>WhichKeyVisual ','<CR>
let g:which_key_map = {}

" hide 1-9
let g:which_key_map.0 = 'which_key_ignore'
let g:which_key_map.1 = 'which_key_ignore'
let g:which_key_map.2 = 'which_key_ignore'
let g:which_key_map.3 = 'which_key_ignore'
let g:which_key_map.4 = 'which_key_ignore'
let g:which_key_map.5 = 'which_key_ignore'
let g:which_key_map.6 = 'which_key_ignore'
let g:which_key_map.7 = 'which_key_ignore'
let g:which_key_map.8 = 'which_key_ignore'
let g:which_key_map.9 = 'which_key_ignore'

" Single mappings
let g:which_key_map.q = [ 'CloseBuffer', 'close buffer' ]
let g:which_key_map.u = [':UndotreeToggle', 'Undotree']
let g:which_key_map.n = [':let @/ = ""', 'no highlight']
let g:which_key_map.d = 'buffer switch'
nmap <leader>d <c-^>

let g:which_key_map.e = {
      \ 'name' : '+fern' ,
      \ 'e' : [':Fern . -drawer -stay -toggle -keep', 'fern'],
      \ 'f' : [':call FernLocateFile()', 'locate file'],
      \ }

" windows
let g:which_key_map.w = {
      \ 'name' : '+windows' ,
      \ 'n' : [':vnew', 'vnew'],
      \ 'N' : [':new', 'new'],
      \ 's' : [':vsplit', 'vspilt'],
      \ 'S' : [':split', 'spilt'],
      \ 'o' : [':only', 'only'],
      \ }

" g is for git
let g:which_key_map.g = {
      \ 'name' : '+git' ,
      \ 'a' : [':Git add %', 'add current'],
      \ 'A' : [':Git add -A', 'add all'],
      \ 'b' : [':Git blame', 'blame'],
      \ 'c' : [':Git commit', 'commit'],
      \ 'g' : [':SignifyHunkDiff', 'show hunk diff'],
      \ 'u' : [':SignifyHunkUndo', 'Undo git hunk'],
      \ 'd' : [':Git diff', 'diff'],
      \ 'D' : [':Git diff --cached', 'diff --cached'],
      \ 'l' : [':Git log', 'log'],
      \ 'P' : [':AsyncRun -focus=0 -mode=term -rows=10 git push', 'git push'],
      \ 's' : [':Gstatus', 'status'],
      \ 'S' : [':Git status', 'status'],
      \ }

nmap <leader>gj <plug>(signify-next-hunk)
let g:which_key_map.g.j = 'next hunk'
nmap <leader>gk <plug>(signify-prev-hunk)
let g:which_key_map.g.k = 'prev hunk'
nmap <leader>gJ 9999<leader>gj
let g:which_key_map.g.J = 'first hunk'
nmap <leader>gK 9999<leader>gk
let g:which_key_map.g.K = 'last hunk'

""" Configuration example
" Echo translation in the cmdline
nmap <silent> <Leader>sc <Plug>Translate
vmap <silent> <Leader>sc <Plug>TranslateV
" Display translation in a window
nmap <silent> <Leader>ss <Plug>TranslateW
vmap <silent> <Leader>ss <Plug>TranslateWV
" Replace the text with translation
nmap <silent> <Leader>sr <Plug>TranslateR
vmap <silent> <Leader>sr <Plug>TranslateRV
" Translate the text in clipboard
nmap <silent> <Leader>sy <Plug>TranslateX

" vim toggle
let g:which_key_map.v = {
      \ 'name' : '+Vim toggle' ,
      \ 'j' : [':call ToggleGj()', 'toggle gj'],
      \ 'v' : [':edit ' . $HOME . '/.dotfiles/.vim/vimrc | :cd ' . $HOME . '/.dotfiles/.vim', 'open vimrc'],
      \ 's' : [':source ' .  $MYVIMRC, 'apply vimrc'],
      \ 'n' : [':set invnumber', 'toggle number'],
      \ 'd' : [':call ToggleDiff()', 'toggle diff'],
      \ 'p' : [':call TogglePaste()', 'toggle paste'],
      \ 'w' : [":call ToggleWrap()", 'toggle wrap'],
      \ 'm' : [":call ToggleMouse()", 'toggle mouse'],
      \ 'i' : [":call ToggleSignColumn()", 'toggle sign'],
      \ }

" g is for git
let g:which_key_map.r = {
      \ 'name' : '+run' ,
      \ }
let g:which_key_map.r.r = "run"

" Visual Mode mappings
vmap <silent> <leader>cB :<c-u>call base64#v_atob()<cr>
vmap <silent> <leader>cb :<c-u>call base64#v_btoa()<cr>

" Regex mappings
" nmap <leader>cB\ :%s/\v()/\=base64#encode(submatch(1))/<home><right><right><right><right><right><right>
" nmap <leader>cb\ :%s/\v()/\=base64#decode(submatch(1))/<home><right><right><right><right><right><right>

vmap <leader>cc :'<,'>SnakeToCamelSel!<cr>
nmap <leader>cc :SnakeToCamelAll!<cr>

vmap <leader>cs :'<,'>CamelToSnakeSel!<cr>
nmap <leader>cs :CamelToSnakeAll!<cr>

vmap <leader>cf <Plug>(coc-format-selected)
nmap <leader>cf <Plug>(coc-format)
let g:which_key_map.c = {
      \ 'name' : '+Code' ,
      \ 'r' : ["<Plug>(coc-rename)", 'rename variable'],
      \ }
let g:which_key_map.c.c = "ToCamel"
let g:which_key_map.c.s = "ToSnake"
let g:which_key_map.c.f = "Autoformat"
let g:which_key_map.c.b = "base64"
let g:which_key_map.c.B = "unbase64"

" +buffer or terminal
let g:which_key_map.t = {
      \ 'name' : '+tab/terminal' ,
      \ 't' : [':call ToggleTerminal()', 'open terminal'],
      \ 'n' : [':enew', 'new buffer'],
      \ }


let g:which_key_map.f = {
      \ 'name' : '+Leaderf/Files' ,
      \ 'c' : [':Leaderf colorscheme', 'colorscheme'],
      \ 'f' : [':Leaderf file', 'file'],
      \ 'r' : [':Leaderf rg', 'rg'],
      \ 'F' : ['<c-w>f', 'open-cursor-file'],
      \ 'b' : [':Leaderf buffer', 'buffer'],
      \ 'm' : [':Leaderf --nowrap mru', 'mru'],
      \ 'h' : [':Leaderf help', 'help'],
      \ 'W' : [':SudaWrite', 'sudo-write'],
      \ 'w' : [':w', 'write'],
      \ 'j' : [':JunkList', 'junk list'],
      \ 'g' : [':JunkFile', 'JunkFile'],
      \ 'l' : [':Leaderf line', 'line'],
      \ 'n' : [':Leaderf filetype', 'filetype'],
      \ }

let g:which_key_map.f.C = {
      \ 'name' : '+Files/convert' ,
      \ 'u' : [':set ff=unix', '2unix'],
      \ 'd' : [':set ff=dos', '2dos'],
      \ }

call which_key#register(',', "g:which_key_map")
