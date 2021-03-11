command! -nargs=+ Log call s:quick_note(<q-args>)
function! s:quick_note(text)
	let text = substitute(a:text, '^\s*\(.\{-}\)\s*$', '\1', '')
	if exists('*writefile') && text != ''
		let filename = get(g:, 'quicknote_file', '~/.vim/quicknote.md')
		let notehead = get(g:, 'quicknote_head', '- ')
		let notetime = strftime("[%Y-%m-%d %H:%M:%S] ")
		let realname = expand(filename)
		call writefile([notehead . notetime . text], realname, 'a')
		checktime
		echo notetime . text
	endif
endfunc

" Open junk file.
command! -nargs=0 JunkFile call s:open_junk_file()
function! s:open_junk_file()
	let junk_dir = '~/junk-file'
	let junk_dir = junk_dir . strftime('/%Y/%m')
	let real_dir = expand(junk_dir)
	if !isdirectory(real_dir)
		call mkdir(real_dir, 'p')
	endif

	let filename = junk_dir . '/'
	let filename = tr(filename, '\', '/')
    let partname = input('Junk Code: ', strftime('%Y-%m-%d-%H%M%S.'))
	let filename = filename . partname
	if partname != ''
		execute 'edit ' . fnameescape(filename)
	endif
endfunction

command! -nargs=0 SaveAsJunkFile call s:save_as_junk_file()
function! s:save_as_junk_file()
	let junk_dir = '~/junk-file'
	let junk_dir = junk_dir . strftime('/%Y/%m')
	let real_dir = expand(junk_dir)
	if !isdirectory(real_dir)
		call mkdir(real_dir, 'p')
	endif

	let filename = junk_dir . '/'
	let filename = tr(filename, '\', '/')
    let partname = input('Junk Code: ', strftime('%Y-%m-%d-%H%M%S.'))
	let filename = filename . partname
	if partname != ''
		execute 'w ' . fnameescape(filename)
	endif
endfunction

command! -nargs=0 JunkList call s:open_junk_list()
function! s:open_junk_list()
	let junk_dir = '~/junk-file'
	" let junk_dir = expand(junk_dir) . strftime('/%Y/%m')
	let junk_dir = tr(junk_dir, '\', '/')
	echo junk_dir
	exec "Leaderf file " . fnameescape(expand(junk_dir))
endfunction
