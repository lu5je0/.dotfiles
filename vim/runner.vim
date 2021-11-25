command! -nargs=0 RunFile call RunFile()

function! s:run_tmux(opts)
    " asyncrun has temporarily changed dir for you
    " getcwd() in the runner function is the target directory defined in `-cwd=xxx`  
    let cwd = getcwd()   
    call VimuxRunCommand('cd ' . shellescape(cwd) . '; ' . a:opts.cmd)
endfunction

let g:asyncrun_runner = get(g:, 'asyncrun_runner', {})
let g:asyncrun_runner.tmux = function('s:run_tmux')

function! RunFileInner(cmd, append)
    let pos = ''
    if exists('$TMUX')
        let pos = 'tmux'
    else
        let pos = 'termhelp'
    endif
    let l:cmd_str = 'AsyncRun -mode=term -pos=' . pos . ' -rows=10 -focus=0 ' . a:cmd . ' "$(VIM_FILEPATH)"'
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

nmap <silent> <leader>rr :RunFile<CR>
