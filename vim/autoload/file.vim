function! file#fern_show_file_info()
    let l:helper = fern#helper#new()
    let l:path = helper.sync.get_cursor_node()['_path']
    echom system("ls -alhd \"" . path . "\"")[0:-2]
endfunction
