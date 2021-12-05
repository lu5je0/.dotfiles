lua require('impatient')
lua require('enhance')
lua require('plugins')
lua require('commands')

runtime settings.vim

if has("gui")
    runtime gvim.vim
endif

runtime functions.vim

runtime mappings.vim
runtime misc.vim
runtime runner.vim
runtime autocmd.vim
if has("mac")
    runtime im.vim
endif

call timer_start(0, 'LoadPlug')
function! LoadPlug(timer) abort
    if has("mac")
        let g:python3_host_prog = '/usr/local/bin/python3'
    endif
    silent! PackerLoad coc.nvim
    silent! PackerLoad vim-textobj-parameter

    if has("wsl")
        silent! PackerLoad im-switcher.nvim
    endif
    set clipboard=unnamed

    hi StatusLine guibg=#5C6370
    hi StatusLineNC guibg=#5C6370
    hi CocHighlightText guibg=#344134
endfunction
