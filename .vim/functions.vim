" 在gj和j之间切换
let g:ToggleGjStauts = 0
function ToggleGj()
    if g:ToggleGjStauts == 0
        nmap j gj
        nmap k gk
        let g:ToggleGjStauts = 1
        echo "gj is enable"
    else
        unmap j
        unmap k
        let g:ToggleGjStauts = 0
        echo "gj is disable"
    endif
endfunction

function LargeFile()
    " file is large from 5MB
    syntax off
    autocmd VimEnter * echo "The file is larger than " . g:LargeFile . " MB, so some options are changed (see .vimrc for details)."
endfunction

function! IsWSL()
    if exists("g:isWsl")
        return g:isWsl
    endif

    if has("unix")
        let lines = readfile("/proc/version")
        if lines[0] =~ "Microsoft"
            let g:isWsl=1
            return 1
        endif
    endif
    let g:isWsl=0
    return 0
endfunction
