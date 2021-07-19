function! visual#runSelectInTerminal()
    call TerminalSend(VisualSelection())
    call TerminalSend("\r")
endfunction
