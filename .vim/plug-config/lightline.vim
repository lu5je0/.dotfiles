let g:lightline = {
      \ 'active': {
      \   'left': [ [ 'mode', 'paste' ], [ 'readonly', 'filename'] ],
      \   'right': [ [ 'lineinfo' ],
      \              [ 'encoding'] ]
      \ },
      \ 'inactive': {
      \   'right': [ [ 'lineinfo' ],
      \              [ 'encoding'] ]
      \ },
      \ 'tabline': {
      \   'left': [ ['buffers'] ],
      \   'right': [ ['filesize'] ],
      \ },
      \ 'component_expand': {
      \   'buffers': 'lightline#bufferline#buffers'
      \ },
      \ 'component_type': {
      \   'buffers': 'tabsel'
      \ },
      \ 'component': {
      \   'filetype': '%{&ft!=#""?&ft:"txt"}',
      \   'lineinfo': '%2p%% ☰ %2l:%L :%2c',
      \   'encoding': '%{&fenc!=#""?&fenc:&enc}[%{&ff}]',
      \ },
      \ 'component_function': {
      \   'filesize': 'FileSize',
      \ }
      \ }

" Symbols {{{
let s:powerline_font              = 1 " Enable for powerline glyphs
if s:powerline_font
  let s:symbol_separator_left     = "\uE0B0"
  let s:symbol_separator_right    = "\uE0B2"
  let s:symbol_subseparator_left  = "\uE0B1"
  let s:symbol_subseparator_right = "\uE0B3"
  let s:symbol_vcs_branch         = "\uE0A0"
else
  let s:symbol_separator_left     = "▏"
  let s:symbol_separator_right    = "▕"
  let s:symbol_subseparator_left  = "│"
  let s:symbol_subseparator_right = "│"
  let s:symbol_vcs_branch         = "\u16B4"
endif
" }}}

let g:lightline.separator        = {'left': s:symbol_separator_left, 'right': s:symbol_separator_right}
let g:lightline.subseparator     = {'left': s:symbol_subseparator_left, 'right': s:symbol_subseparator_right}
let g:lightline#bufferline#enable_nerdfont=1
let g:lightline#bufferline#enable_devicons=1
let g:lightline#bufferline#clickable=1
let g:lightline#bufferline#unicode_symbols=1
let g:lightline#bufferline#show_number=2
let g:lightline#bufferline#number_map = {
\ 0: '⁰', 1: '¹', 2: '²', 3: '³', 4: '⁴',
\ 5: '⁵', 6: '⁶', 7: '⁷', 8: '⁸', 9: '⁹'}
let g:lightline.component_raw = {'buffers': 1}
