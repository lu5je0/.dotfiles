command! -nargs=+ Log call s:quick_note(<q-args>)
function! s:quick_note(text)
	let text = substitute(a:text, '^\s*\(.\{-}\)\s*$', '\1', '')
	if exists('*writefile') && text != ''
		let filename = get(g:, 'quicknote_file', '~/.vim/quicknote.md')
		" let notehead = get(g:, 'quicknote_head', '- ')
		let notetime = strftime("[%Y-%m-%d %H:%M:%S] ")
		let realname = expand(filename)
		call writefile([notetime . text], realname, 'a')
		checktime
		echo notetime . text
	endif
endfunc

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
        let partname = input('Junk Code: ', a:name)
    else
        let partname = input('Junk Code: ', strftime('%Y-%m-%dT%H%M%S-'))
    endif
	let filename = filename . partname
    
    if partname != ''
        return filename
    else
        return ''
    endif
endfunction

" Open junk file.
command! -nargs=0 JunkFile call s:open_junk_file()
function! s:open_junk_file()
    let filename = s:get_junk_filename("")
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

command! -nargs=0 JunkList call s:open_junk_list()
function! s:open_junk_list()
	let junk_dir = '~/junk-file'
	" let junk_dir = expand(junk_dir) . strftime('/%Y/%m')
	let junk_dir = tr(junk_dir, '\', '/')
	echo junk_dir
    silent! py3 from leaderf.tagExpl import *
    silent! py3 tagExplManager.refresh()
    silent! :exec g:Lf_py "fileExplManager.refresh()"
	exec "Leaderf file " . fnameescape(expand(junk_dir))
endfunction
