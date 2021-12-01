local M = {}

function M.setup()
  vim.cmd([[
  nmap <F9> <Plug>VimspectorContinue
  nmap <F8> <Plug>VimspectorStepOver
  nmap <F7> <Plug>VimspectorStepInto

  nmap <S-F7> <Plug>VimspectorStepOut
  nmap <F20> <Plug>VimspectorStepOut

  nmap <S-F9> <Plug>VimspectorRunToCursor
  nmap <F21> <Plug>VimspectorRunToCursor

  nmap <F10> <Plug>VimspectorToggleBreakpoint

  nmap <S-F10> <Plug>VimspectorToggleConditionalBreakpoint
  nmap <F22> <Plug>VimspectorToggleConditionalBreakpoint

  nmap <F12> :call vimspector#Reset()<cr>

  tmap <silent> <C-Q> <C-\><C-N>
  ]])
  vim.g.vimspector_install_gadgets = {'debugpy'}
end

return M
