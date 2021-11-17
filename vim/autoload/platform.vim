function! platform#is_wsl()
    if !has('wsl')
        return 0
    endif

    if exists("g:isWsl")
        return g:isWsl
    endif

    let lines = readfile("/proc/version")
    if lines[0] =~ "WSL2"
        let g:isWsl = 2
        return 2
    else
        let g:isWsl = 1
        return 1
    endif

    let g:isWsl = 0
    return 0
endfunction
