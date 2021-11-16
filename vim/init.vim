lua require('impatient')
lua require('plugins')

" runtime 加载.vim {{{
runtime settings.vim

if has("win32")
    runtime escalt.vim
endif

if has("gui")
    runtime gvim.vim
endif

runtime functions.vim
" }}}

" 主题配置 {{{
colorscheme one
set bg=dark
hi TSPunctBracket guifg=#ABB2BF
" }}}

runtime mappings.vim
runtime misc.vim
runtime runner.vim
runtime autocmd.vim

call timer_start(0, 'LoadPlug')
function! LoadPlug(timer) abort
    if has("mac")
        let g:python3_host_prog  = '/usr/local/bin/python3'
    endif
    runtime im.vim
    silent! PackerLoad coc.nvim
    silent! PackerLoad vim-textobj-parameter

    let wsl_version = platform#is_wsl()
    if wsl_version == 1 || wsl_version == 2
        silent! PackerLoad im-switcher
    endif
    set clipboard=unnamed
endfunction
