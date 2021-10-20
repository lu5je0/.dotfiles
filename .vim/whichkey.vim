set timeoutlen=500

" highlight default link WhichKey          Function
" highlight default link WhichKeyDesc      Function
highlight default link WhichKeySeperator String
highlight default link WhichKeyGroup Text

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

nnoremap <silent><leader>1 :lua require'bufferline'.go_to_buffer(1, true)<cr>
nnoremap <silent><leader>2 :lua require'bufferline'.go_to_buffer(2, true)<cr>
nnoremap <silent><leader>3 :lua require'bufferline'.go_to_buffer(3, true)<cr>
nnoremap <silent><leader>4 :lua require'bufferline'.go_to_buffer(4, true)<cr>
nnoremap <silent><leader>5 :lua require'bufferline'.go_to_buffer(5, true)<cr>
nnoremap <silent><leader>6 :lua require'bufferline'.go_to_buffer(6, true)<cr>
nnoremap <silent><leader>7 :lua require'bufferline'.go_to_buffer(7, true)<cr>
nnoremap <silent><leader>8 :lua require'bufferline'.go_to_buffer(8, true)<cr>
nnoremap <silent><leader>9 :lua require'bufferline'.go_to_buffer(9, true)<cr>
nnoremap <silent><leader>0 :BufferLinePick<CR>

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
let g:which_key_map.Q = [ 'QuitForce', 'quit force' ]
let g:which_key_map.u = [':UndotreeToggle', 'undotree']
let g:which_key_map.i = [':Vista!!', 'vista']
let g:which_key_map.n = [':let @/ = ""', 'no highlight']
let g:which_key_map.d = 'buffer switch'
let g:which_key_map.e = [":Fern . -drawer -stay -toggle -keep", "fern"]
let g:which_key_map['/'] = [":call eregex#toggle()", "eregex toggle"]

nmap <leader>d <c-^>

" windows
let g:which_key_map.a = [":call Calc()", "calcultor"]

" windows
let g:which_key_map.w = {
      \ 'name' : '+windows' ,
      \ 'n' : [':vnew', 'vnew'],
      \ 'N' : [':new', 'new'],
      \ 's' : [':vsplit', 'vspilt'],
      \ 'S' : [':split', 'spilt'],
      \ 'q' : [':only', 'break window'],
      \ 'd' : [':BufferLinePickSplit', 'spilit with'],
      \ 'p' : [':BufferLinePick', 'buffer pick'],
      \ }
nmap <leader>wu <c-w>x
let g:which_key_map.w.u = 'swap buffer'

" g is for git
let g:which_key_map.g = {
      \ 'name' : '+git' ,
      \ 'a' : [":silent! w | Git add % | echo 'git added'", 'add current'],
      \ 'A' : [':Git add -A', 'add all'],
      \ 'b' : [':Git blame', 'blame'],
      \ 'c' : [':Git commit', 'commit'],
      \ 'g' : [':SignifyHunkDiff', 'show hunk diff'],
      \ 'u' : [':SignifyHunkUndo', 'undo git hunk'],
      \ 'd' : [':Git diff', 'diff'],
      \ 'D' : [':Git diff --cached', 'diff --cached'],
      \ 'v' : [':Gvdiffsplit!', 'gvdiffsplit'],
      \ 'l' : [':Flogsplit', 'git log'],
      \ 'i' : [':Gist -l', 'gist'],
      \ 'P' : [':AsyncRun -focus=0 -mode=term -rows=10 git push', 'git push'],
      \ 's' : [':Gstatus', 'status'],
      \ 'S' : [':Git status', 'status'],
      \ }

" plugin
let g:which_key_map.p = {
      \ 'name' : '+git' ,
      \ 'i' : [":echo 'PackerInstall' | PackerInstall", 'plugin install'],
      \ 'C' : [":echo 'PackerClean' | PackerClean", 'plugin clean'],
      \ 'c' : [":echo 'PackerCompile' | PackerCompile", 'plugin compile'],
      \ 'u' : [":echo 'PackerUpdate' | PackerUpdate", 'plugin update'],
      \ }

let g:which_key_map.s = {
            \ 'name' : '+translate',
            \ 's' : 'translate popup',
            \ 'a' : 'say it',
            \ 'r' : 'translate replace',
            \ 'c' : 'translate',
            \ }

" Echo translation in the cmdline
nmap <silent> <Leader>sc <Plug>Translate
vmap <silent> <Leader>sc <Plug>TranslateV

" say it
nmap <silent> <Leader>sa :call misc#say_it()<cr><Plug>TranslateW
vmap <silent> <Leader>sa :call misc#visual_say_it()<cr><Plug>TranslateWV

" vmap <silent> <Leader>sc <Plug>TranslateV
" Display translation in a window
nmap <silent> <Leader>ss <Plug>TranslateW
vmap <silent> <Leader>ss <Plug>TranslateWV
" Replace the text with translation
nmap <silent> <Leader>sr <Plug>TranslateR
vmap <silent> <Leader>sr <Plug>TranslateRV

" vim toggle
let g:which_key_map.v = {
      \ 'name' : '+vim',
      \ 'j' : [':call ToggleGj()', 'toggle gj'],
      \ 'c' : [':set ic!', 'toggle case insensitive'],
      \ 'a' : [':call AutoPairsToggle()', 'toggle auto pairs'],
      \ 'v' : [':edit ' . $HOME . '/.dotfiles/.vim/vimrc | :cd ' . $HOME . '/.dotfiles/.vim', 'open vimrc'],
      \ 's' : [':source ' .  $MYVIMRC, 'apply vimrc'],
      \ 'b' : [":call ToggleSignColumn()", 'toggle blame'],
      \ 'n' : [':set invnumber', 'toggle number'],
      \ 'd' : [':call ToggleDiff()', 'toggle diff'],
      \ 'p' : [':call TogglePaste()', 'toggle paste'],
      \ 'w' : [":call ToggleWrap()", 'toggle wrap'],
      \ 'm' : [":call ToggleMouse()", 'toggle mouse'],
      \ 'i' : [":ToggleSaveLastIme", 'toggle-save-last-ime'],
      \ 'h' : [":call hexedit#ToggleHexEdit()", 'toggle hexedit'],
      \ 'l' : [":set cursorline!", 'toggle cursorline'],
      \ }

let g:which_key_map.v.f = {
      \ 'name' : '+foldmethod',
      \ 'm' : [":set fdm=manual | echo \"fdm = manual\"", 'manual'],
      \ 's' : [":set fdm=sytanx | echo \"fdm = sytanx\"", 'sytanx'],
      \ 'e' : [":set fdm=expr | echo \"fdm = expr\"", 'expr'],
      \ 'i' : [":set fdm=indent | echo \"fdm = indent\"", 'indent'],
      \ 'n' : [":set fdm=marker | echo \"fdm = marker\"", 'marker'],
      \ 'd' : [":set fdm=diff | echo \"fdm = diff\"", 'diff'],
      \ }

" g is for git
let g:which_key_map.r = {
      \ 'name' : '+run',
      \ 'r': "run"
      \ }

" Symbol renaming.
nmap <leader>cr <Plug>(coc-rename)

vmap <leader>cf <Plug>(coc-format-selected)
nmap <leader>cf <Plug>(coc-format)

" Applying codeAction to the selected region.
" Example: `<leader>aap` for current paragraph
xmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>
nmap <silent> <leader>cc <Plug>(coc-codeaction-selected)<cr>

      " \ 'c' : ["<Plug>(coc-codeaction-selected)<cr>", 'codeaction'],
let g:which_key_map.c = {
      \ 'name' : '+code' ,
      \ 'r' : ["<Plug>(coc-rename)", 'rename-variable'],
      \ 'c' : "code-action",
      \ 'f' : "auto-format",
      \ }

" +buffer or terminal
let g:which_key_map.t = {
      \ 'name' : '+tab/terminal' ,
      \ 't' : [':call TerminalToggle()', 'terminal'],
      \ 'b' : [':call CDTerminalToCWD()', 'terminal-cd-buffer-dir'],
      \ 'o' : [ ':call buffer#CloseOtherBuffers()', 'close-other-buffers' ],
      \ 'n' : [':enew', 'new-buffer'],
      \ }


let g:which_key_map.f = {
      \ 'name' : '+leaderf/files',
      \ 'a' : [":echom 'detecting' | GuessLang", "GuessLang"],
      \ 'C' : [':Leaderf colorscheme', 'colorscheme'],
      \ 'f' : [':Leaderf file', 'file'],
      \ 'g' : [':Leaderf --recall', 'recall'],
      \ 'r' : [':Leaderf rg', 'rg'],
      \ 'e' : [':call FernLocateFile()', 'locate-file'],
      \ 'F' : ['<c-w>f', 'open-cursor-file'],
      \ 'b' : [':Leaderf buffer', 'buffer'],
      \ 'm' : [':Leaderf --nowrap mru', 'mru'],
      \ 'h' : [':Leaderf help', 'help'],
      \ 'W' : [':SudaWrite', 'sudo-write'],
      \ 'v' : [":Fern ~/.vim -drawer -keep", 'fern .vim/'],
      \ 'w' : [':w', 'write'],
      \ 'j' : [':JunkList', 'junk-list'],
      \ 'J' : [':JunkFile', 'new-junk-file'],
      \ 'u' : [':SaveAsJunkFile', 'save-as-junk-file'],
      \ 'l' : [':Leaderf line', 'line'],
      \ 'n' : [':Leaderf filetype', 'filetype'],
      \ }

let g:which_key_map.f.x = {
      \ 'name' : '+encoding',
      \ 'a' : [':set ff=unix', '2unix'],
      \ 'b' : [':set ff=dos', '2dos'],
      \ 'u' : [':set fileencoding=utf8', 'convert to utf8'],
      \ 'g' : [':set fileencoding=GB18030', 'convert to gb18030'],
      \ }

let g:which_key_map.x = {
      \ 'name' : '+text',
      \ 'q' : "繁体转简体",
      \ 'Q' : "简体转繁体",
      \ 'm' : [':%s/\r$//', '移除^M'],
      \ 'b' : "base64",
      \ 'B' : "unbase64",
      \ 's' : "escape string",
      \ 'u' : "Escape Unicode",
      \ 'U' : "Unescape Unicode",
      \ 'h' : "url encode",
      \ 'H' : "url decode",
      \ 'c' : [":call edit#CountSelectionRegion()", "count in the selection region"],
      \ }

"----------------------------------------------------------------------
" 繁体简体
"----------------------------------------------------------------------
vmap <leader>xq :!opencc -c t2s<cr>
nmap <leader>xq :%!opencc -c t2s<cr>

vmap <leader>xQ :!opencc -c s2t<cr>
nmap <leader>xQ :%!opencc -c s2t<cr>


"----------------------------------------------------------------------
" base64
"----------------------------------------------------------------------
vmap <silent> <leader>xB :<c-u>call base64#v_atob()<cr>
vmap <silent> <leader>xb :<c-u>call base64#v_btoa()<cr>


"----------------------------------------------------------------------
" unicode escape
"----------------------------------------------------------------------
vmap <silent> <leader>xu :<c-u>call ReplaceSelect("UnicodeEscapeString")<cr>
vmap <silent> <leader>xU :<c-u>call ReplaceSelect("UnicodeUnescapeString")<cr>

"----------------------------------------------------------------------
" text escape
"----------------------------------------------------------------------
vmap <silent> <leader>xs :<c-u>call ReplaceSelect("EscapeText")<cr>
" vmap <silent> <leader>xU :<c-u>call ReplaceSelect("UnicodeUnescapeString")<cr>

"----------------------------------------------------------------------
" url encode
"----------------------------------------------------------------------
nmap <leader>xh :%!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
nmap <leader>xH :%!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>

vnoremap <leader>xh :!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
vnoremap <leader>xH :!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>


call which_key#register(',', "g:which_key_map")
