function! fileinfo#fern_show_file_info()
    let l:helper = fern#helper#new()
    let l:path = helper.sync.get_cursor_node()['_path']
    let l:info = system("ls -alh \"" . path . "\"")
    echom l:info[0:-2]
endfunction
