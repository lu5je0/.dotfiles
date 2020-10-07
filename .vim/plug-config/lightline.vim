let g:lightline = {
      \ 'colorscheme': 'one',
      \ }

let g:lightline.active = {
    \ 'left': [ [ 'mode', 'paste' ],
    \           [ 'readonly', 'filename'] ],
    \ 'right': [ [ 'lineinfo' ],
    \            [ 'percent' ],
    \            [ 'fileformat', 'fileencoding', 'filetype' ] ] }

let g:lightline.inactive = {
    \ 'left': [ [ 'readonly', 'filename'] ],
    \ 'right': [ [ 'lineinfo' ],
    \            [ 'percent' ],
    \            [ 'fileformat', 'fileencoding', 'filetype' ] ] }


let g:lightline.component = {
    \ 'filetype': '%{&ft!=#""?&ft:"txt"}',
    \ 'lineinfo': '%3l:%-2c',
    \ }
