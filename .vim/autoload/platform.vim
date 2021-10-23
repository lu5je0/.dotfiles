function! platform#is_wsl()
    if exists("g:isWsl")
        return g:isWsl
    endif

    if has("mac")
        return 0
    elseif has("unix")
        let lines = readfile("/proc/version")
        if lines[0] =~ "Microsoft"
            let g:isWsl = 1
            return 1
        elseif lines[0] =~ "WSL2"
            let g:isWsl = 2
            return 2
        endif
    endif
    let g:isWsl = 0
    return 0
endfunction
