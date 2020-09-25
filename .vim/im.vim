if !has("mac") && IsWSL() == 1
    let g:im_select_default=1033
endif

" mac下输入法切换问题
if has("mac") && has("gui")
    set noimd
    set imi=2
    set ims=2
endif

" 退出vim时 恢复默认输入法
au VimLeave * call im_select#on_insert_enter()
