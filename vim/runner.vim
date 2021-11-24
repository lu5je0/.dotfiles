command! -nargs=0 RunFile call RunFile()

function! RunFileInner(cmd, append)
    let l:cmd_str = 'AsyncRun -mode=term -pos=termhelp -rows=10 -focus=0 ' . a:cmd . ' "$(VIM_FILEPATH)"'

    exe l:cmd_str . a:append
endfunction

function! RunFile()
    let file_type = &filetype
    if file_type == 'vim'
        w
        so %
    elseif file_type == 'python'
        if has("win32") || has("win64")
            call RunFileInner("python", "")
        else 
            call RunFileInner("python3", "")
        endif
    elseif file_type == 'java'
        call RunFileInner("java", "")
    elseif file_type == 'c'
        call RunFileInner("gcc", " && ./a.out && rm ./a.out")
    elseif file_type == 'sh'
        call RunFileInner("bash", "")
    elseif file_type == 'javascript'
        call RunFileInner("node", "")
    elseif file_type == 'go'
        call RunFileInner("go run", "")
    elseif file_type == 'lua'
        call RunFileInner("luajit", "")
    endif
endfunction

nmap <leader>rr :RunFile<CR>
