" nmap <leader>rr :AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python3 "$(VIM_FILEPATH)"<CR>

command! -nargs=0 RunFile call RunFile()
function! RunFile()
    let file_type = &filetype
    if file_type == 'vim'
        w
        so %
    elseif file_type == 'python'
        if has("win32") || has("win64")
            AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python "$(VIM_FILEPATH)"
        else 
            AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 python3 "$(VIM_FILEPATH)"
        endif
    elseif file_type == 'java'
        AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 java "$(VIM_FILEPATH)"
    elseif file_type == 'c'
        AsyncRun -mode=term -pos=bottom -rows=10 -focus=0 gcc "$(VIM_FILEPATH)" && ./a.out && rm ./a.out
    endif
endfunction

nmap <leader>rr :RunFile<CR>
