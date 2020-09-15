" 在gj和j之间切换
let g:ToggleGjStauts = 0
function ToggleGj()
    if g:ToggleGjStauts == 0
        nmap j gj
        nmap k gk
        let g:ToggleGjStauts = 1
    else
        unmap j
        unmap k
        let g:ToggleGjStauts = 0
    endif
endfunction
