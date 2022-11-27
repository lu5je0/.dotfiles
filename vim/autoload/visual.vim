function! visual#replace(text)
    let reg_tmp = @a
    let @a = a:text
    normal! "ap
    let @a = reg_tmp
    unlet reg_tmp
endfunction

function! visual#replace_by_fn(fn)
	" Preserve line breaks
	let l:paste = &paste
	set paste
	" Reselect the visual mode text
	normal! gv
	" Apply transformation to the text
	execute "normal! c\<c-r>=" . a:fn . "(@\")\<cr>\<esc>"
	" Select the new text
	normal! `[v`]h
	" Revert to previous mode
	let &paste = l:paste
endfunction

function! visual#star_search_set(cmdtype,...)
  let temp = @"
  normal! gvy
  if !a:0 || a:1 != 'raw'
    let @" = escape(@", a:cmdtype.'\*')
  endif
  let @/ = substitute(@", '\n', '\\n', 'g')
  let @/ = substitute(@/, '\[', '\\[', 'g')
  let @/ = substitute(@/, '\~', '\\~', 'g')
  let @/ = substitute(@/, '\.', '\\.', 'g')
  let @" = temp
endfunction
