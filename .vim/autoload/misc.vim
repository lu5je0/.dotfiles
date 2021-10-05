function! misc#fold_text()
  let l:lpadding = &fdc
  redir => l:signs
    execute 'silent sign place buffer='.bufnr('%')
  redir End
  let l:lpadding += l:signs =~ 'id=' ? 2 : 0

  if exists("+relativenumber")
    if (&number)
      let l:lpadding += max([&numberwidth, strlen(line('$'))]) + 1
    elseif (&relativenumber)
      let l:lpadding += max([&numberwidth, strlen(v:foldstart - line('w0')), strlen(line('w$') - v:foldstart), strlen(v:foldstart)]) + 1
    endif
  else
    if (&number)
      let l:lpadding += max([&numberwidth, strlen(line('$'))]) + 1
    endif
  endif

  " expand tabs
  let l:start = substitute(getline(v:foldstart), '\t', repeat(' ', &tabstop), 'g')
  let l:end = substitute(substitute(getline(v:foldend), '\t', repeat(' ', &tabstop), 'g'), '^\s*', '', 'g')

  let l:info = ' (' . (v:foldend - v:foldstart) . ' lines)'
  let l:infolen = strlen(substitute(l:info, '.', 'x', 'g'))
  let l:width = winwidth(0) - l:lpadding - l:infolen

  let l:separator = ' … '
  let l:separatorlen = strlen(substitute(l:separator, '.', 'x', 'g'))
  let l:start = strpart(l:start , 0, l:width - strlen(substitute(l:end, '.', 'x', 'g')) - l:separatorlen)
  let l:text = l:start . trim(getline(v:foldstart + 1)) . '...' . l:end

  return l:text . repeat(' ', l:width - strlen(substitute(l:text, ".", "x", "g")) + 1) . l:info
endfunction

function misc#execute_command_for_word(cmd)
   let l:word = expand("<cword>")
   execute 'silent exec "!' . a:cmd . ' ' . l:word . '"'
endfu 

function misc#say(word)
    echon a:word
    call jobstart("say -v Alex " . a:word)
endfunction

function misc#say_it()
    call misc#say(expand("<cword>"))
endfunction

function misc#visual_say_it()
    call misc#say(visual#visual_selection())
endfunction
