" let g:fern#disable_default_mappings=1
let g:fern#renderer = "nerdfont"
" let g:fern#smart_cursor = "hide"
let g:fern#disable_drawer_smart_quit = 0
let g:fern#renderer#nerdfont#root_symbol = "≡ "

function! s:init_fern() abort
  " hi FernBranchText ctermfg=16 guifg=#61afef
  " yellow
  hi FernBranchText ctermfg=16 guifg=#E5C07B

  hi FernRootText ctermfg=16 guifg=#E06C75

  " hide sign
  setlocal scl=no
  setlocal nonumber

  " Define NERDTree like mappings
  " nmap <buffer> <nowait> <leader> <C-W>l<leader>
  nmap <buffer> <C-L> <C-W>l
  nmap <buffer> <C-H> <C-W>h
  nmap <buffer> o <Plug>(fern-action-open-or-expand)
  nmap <buffer> <cr> <Plug>(fern-action-open-or-expand)
  nmap <buffer> go <Plug>(fern-action-open:edit)<C-w>p
  nmap <buffer> t <Plug>(fern-action-open:tabedit)
  nmap <buffer> T <Plug>(fern-action-open:tabedit)gT
  nmap <buffer> i <Plug>(fern-action-open:split)
  nmap <buffer> gi <Plug>(fern-action-open:split)<C-w>p
  nmap <buffer> s <Plug>(fern-action-open:vsplit)
  nmap <buffer> gs <Plug>(fern-action-open:vsplit)<C-w>p
  nmap <buffer> ma <Plug>(fern-action-new-path)
  nmap <buffer> P gg
  nmap <buffer> C <Plug>(fern-action-enter)
  nmap <buffer> u <Plug>(fern-action-leave)
  nmap <buffer> r <Plug>(fern-action-reload)
  nmap <buffer> R gg<Plug>(fern-action-reload)<C-o>
  nmap <buffer> cd <Plug>(fern-action-cd)
  nmap <buffer> CD gg<Plug>(fern-action-cd)<C-o>
  nmap <buffer> I <Plug>(fern-action-hidden:toggle)

  nmap <buffer> q :<C-u>quit<CR>
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
