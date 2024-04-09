function! s:get_junk_filename(name)
	let junk_dir = '~/junk-file'
	let junk_dir = junk_dir . strftime('/%Y/%m')
	let real_dir = expand(junk_dir)
	if !isdirectory(real_dir)
		call mkdir(real_dir, 'p')
	endif

	let filename = junk_dir . '/'
	let filename = tr(filename, '\', '/')
    if a:name != ""
        let partname = input('Junk File: ', a:name)
    else
        let partname = input('Junk File: ', strftime('%Y-%m-%dT%H%M%S-'))
    endif
	let filename = filename . partname
    
    if partname != ''
        return filename
    else
        return ''
    endif
endfunction

" Open junk file.
command! -nargs=* NewJunkFile call s:open_junk_file(<f-args>)
function! s:open_junk_file(...)
    let filename = ''
    if len(a:000) > 0 && a:000[0] != ''
        let filename = a:000[0]
    endif
    let filename = s:get_junk_filename(filename)
    
	if filename != ''
		execute 'edit ' . fnameescape(filename)
	endif
endfunction

command! -nargs=* SaveAsJunkFile call s:save_as_junk_file(<f-args>)
function! s:save_as_junk_file(...)
    let cur_file_name = expand('%:t')
    if len(a:000) > 0 && a:000[0] != ''
        let cur_file_name = a:000[0]
    endif
    let filename = s:get_junk_filename(cur_file_name)
	if filename != ''
		execute 'w ' . fnameescape(filename)
	endif
endfunction
