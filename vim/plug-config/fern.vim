let g:fern#disable_default_mappings=0
let g:fern#renderer = "nerdfont"
" let g:fern#smart_cursor = "hide"
let g:fern#disable_drawer_smart_quit = 0
let g:fern#renderer#nerdfont#root_symbol = "≡ "
let g:fern#disable_viewer_spinner=1
let g:fern#default_exclude = '\.\(swp\|git\)'
let g:fern#drawer_width=22
let g:fern#mark_symbol="•"
" let g:fern#disable_drawer_auto_resize=1

function! TerminalSendInner() abort
    let helper = fern#helper#new()
    let path = helper.sync.get_cursor_node()['_path']
    call TerminalSend('cd ' . fnamemodify(path, ":p:h"))
	call TerminalSend("\r")
endfunction

" functions
" locate file
function! FernLocateFile() abort
    let cur_file_path = expand('%:p:h')
    let working_dir = getcwd()
    if stridx(cur_file_path, working_dir) != -1
        :Fern . -reveal=% -drawer -keep
    else
        :Fern %:h -reveal=% -drawer -keep
    endif
endfunction

function! s:init_fern() abort
  " hi FernBranchText ctermfg=16 guifg=#61afef
  " yellow
  hi FernBranchText ctermfg=16 guifg=#E5C07B

  " file Fern
  hi FernRootText ctermfg=16 guifg=#E06C75

  " hide sign
  setlocal scl=auto
  setlocal nonumber

  mapclear! <buffer>

  silent! unmap <buffer> t

  nmap <buffer> <C-L> <C-W>l
  nmap <buffer> <C-H> <C-W>h
  nmap <buffer> <C-J> <C-W>j
  nmap <buffer> <C-K> <C-W>k

  nmap <buffer><expr>
              \ <Plug>(fern-my-expand-or-collapse)
              \ fern#smart#leaf(
              \   "\<Plug>(fern-action-collapse)",
              \   "\<Plug>(fern-action-expand:stay)",
              \   "\<Plug>(fern-action-collapse)",
              \ )
  nmap <buffer><nowait> o <Plug>(fern-my-expand-or-collapse)
  nmap <buffer><nowait> <space> <Plug>(fern-action-mark:toggle)j

  nmap <buffer> yy <Plug>(fern-action-clipboard-copy)
  nmap <buffer> dd <Plug>(fern-action-clipboard-move)
  nmap <buffer> D <Plug>(fern-action-remove)
  nmap <buffer> yp <Plug>(fern-action-yank:path)
  nmap <buffer> yn <Plug>(fern-action-yank:label)
  nmap <buffer> cw <Plug>(fern-action-rename)

  nmap <silent> <buffer> <expr> <Plug>(fern-quit-or-close-preview) fern_preview#smart_preview("\<Plug>(fern-action-preview:close)", ":q\<CR>")
  nmap <silent> <buffer> <expr> <Plug>(fern-esc-or-close-preview) fern_preview#smart_preview("\<Plug>(fern-action-preview:close)", "<c-w>l")
  nmap <silent> <buffer> p <Plug>(fern-action-preview:toggle)
  nmap <buffer> q <Plug>(fern-quit-or-close-preview)
  nmap <buffer> <ESC> <Plug>(fern-esc-or-close-preview)
  nmap <buffer> P gg

  nmap <buffer> <cr> <Plug>(fern-action-open-or-expand)
  nmap <buffer> go <Plug>(fern-action-open:edit)<C-w>p
  nmap <buffer> t :call TerminalSendInner()<cr><C-w>ji
  nmap <buffer> i <Plug>(fern-action-open:split)
  nmap <buffer> gi <Plug>(fern-action-open:split)<C-w>p
  nmap <buffer> s <Plug>(fern-action-open:vsplit)
  nmap <buffer> gs <Plug>(fern-action-open:vsplit)<C-w>p
  nmap <buffer> mk <Plug>(fern-action-new-dir)
  nmap <buffer> ma <Plug>(fern-action-new-file)
  nmap <buffer> mv <Plug>(fern-action-move)
  nmap <buffer> mp <Plug>(fern-action-clipboard-paste)
  nmap <buffer> mv <Plug>(fern-action-move)
  nmap <buffer> m <Nop>
  nmap <buffer> c <Nop>
  silent ! unmap <buffer> fe
  silent ! unmap <buffer> fi
  nmap <buffer><nowait> f :call file#fern_show_file_info()<cr>

  nmap <buffer> C <Plug>(fern-action-cd)<Plug>(fern-action-enter)
  nmap <buffer> H :Fern ~ -drawer -stay -keep<cr>
  nmap <buffer> u <Plug>(fern-action-leave)
  " map <buffer> U ucd todo
  nmap <buffer> r <Plug>(fern-action-reload)
  nmap <buffer> <silent> R :Fern .<cr>
  nmap <silent> <buffer> cd <Plug>(fern-action-cd):echo "cd " . getcwd()<cr>
  nmap <buffer> I <Plug>(fern-action-hidden:toggle)

  nmap <buffer> <leader>d <C-W>l<leader>d 
  nmap <buffer> <leader>1 <C-W>l<leader>1 
  nmap <buffer> <leader>2 <C-W>l<leader>2 
  nmap <buffer> <leader>3 <C-W>l<leader>3 
  nmap <buffer> <leader>4 <C-W>l<leader>4 
  nmap <buffer> <leader>5 <C-W>l<leader>5 
  nmap <buffer> <leader>6 <C-W>l<leader>6 
  nmap <buffer> <leader>7 <C-W>l<leader>7 
  nmap <buffer> <leader>8 <C-W>l<leader>8 
  nmap <buffer> <leader>9 <C-W>l<leader>9 
  nmap <buffer> <leader>ff <C-W>l<leader>ff
  nmap <buffer> <leader>tn <C-W>l<leader>tn
  nmap <buffer> <leader>fr <C-W>l<leader>fr
  nmap <buffer> <leader>fm <C-W>l<leader>fm
  nmap <buffer> <leader>fb <C-W>l<leader>fb
endfunction

augroup fern-custom
  autocmd!
  autocmd FileType nerdtree,startify,fern call glyph_palette#apply()
  autocmd FileType fern call s:init_fern()
augroup END
