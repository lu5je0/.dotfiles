command! -nargs=0 RunFile call RunFile()
command! -nargs=0 LuaDevOn let g:lua_dev=1
command! -nargs=0 LuaDevOff let g:lua_dev=0

function! RunFileInner(cmd, append)
    w
    call v:lua.require("core.terminal").send_to_terminal(a:cmd .. ' ' .. expand('%:p') .. a:append, {"go_back": 1})
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
        if get(g:, 'lua_dev', 1) == 1
            luafile %
        else
            call RunFileInner("luajit", "")
        endif
    endif
endfunction

nmap <silent> <leader>rr :RunFile<CR>
