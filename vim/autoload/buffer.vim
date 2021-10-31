" 关闭其它标签
function! buffer#CloseOtherBuffers()
    let choice = confirm("Close other buffers?", "&No\n&Yes")
    if choice == 2
        :silent BufOnly!
    endif
endfunction
