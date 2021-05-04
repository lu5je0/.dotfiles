let g:fern#disable_default_mappings=0
let g:fern#renderer = "nerdfont"
" let g:fern#smart_cursor = "hide"
let g:fern#disable_drawer_smart_quit = 0
let g:fern#renderer#nerdfont#root_symbol = "≡ "
let g:fern#disable_viewer_spinner=1
let g:fern#default_exclude = '\.\(swp\|git\)'
let g:fern#drawer_width=22


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
  nmap <buffer> dD <Plug>(fern-action-remove)
  nmap <buffer> pp <Plug>(fern-action-clipboard-paste)
  nmap <buffer> yp <Plug>(fern-action-yank:path)
  nmap <buffer> yn <Plug>(fern-action-yank:label)
  nmap <buffer> cw <Plug>(fern-action-rename)
  nmap <buffer> p <Nop>

  nmap <buffer> <cr> <Plug>(fern-action-open-or-expand)
  nmap <buffer> go <Plug>(fern-action-open:edit)<C-w>p
  nmap <buffer> T <Plug>(fern-action-terminal:bottom)
  nmap <buffer> i <Plug>(fern-action-open:split)
  nmap <buffer> gi <Plug>(fern-action-open:split)<C-w>p
  nmap <buffer> s <Plug>(fern-action-open:vsplit)
  nmap <buffer> gs <Plug>(fern-action-open:vsplit)<C-w>p
  nmap <buffer> mk <Plug>(fern-action-new-dir)
  nmap <buffer> ma <Plug>(fern-action-new-file)
  nmap <buffer> mv <Plug>(fern-action-move)
  nmap <buffer> m <Nop>

  nmap <buffer> C <Plug>(fern-action-cd)<Plug>(fern-action-enter)
  nmap <buffer> u <Plug>(fern-action-leave)
  nmap <buffer> r <Plug>(fern-action-reload)
  nmap <buffer> <silent> R :Fern .<cr>
  nmap <buffer> cd <Plug>(fern-action-cd)
  nmap <buffer> I <Plug>(fern-action-hidden:toggle)
  nmap <buffer> <ESC> <C-W>l

  nmap <buffer> q :<C-u>quit<CR>
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
  nmap <buffer> <leader>fr <C-W>l<leader>fr
  nmap <buffer> <leader>fm <C-W>l<leader>fm
  nmap <buffer> <leader>fb <C-W>l<leader>fb
endfunction

augroup fern-custom
  autocmd! *
  autocmd FileType fern call s:init_fern()
augroup END

augroup my-glyph-palette
  autocmd! *
  autocmd FileType fern call glyph_palette#apply()
  autocmd FileType nerdtree,startify call glyph_palette#apply()
augroup END


" functions
" locate file
function! FernLocateFile() abort
    let cur_file_path = expand('%:p:h')
    let working_dir = getcwd()
    if stridx(cur_file_path, working_dir) != -1
        :Fern . -reveal=% -drawer -stay
    else
        :Fern %:h -reveal=% -drawer -stay
    endif
endfunction
