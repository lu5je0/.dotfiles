local M = {}

function M.setup()
  vim.cmd([[
  nmap <F9> <Plug>VimspectorContinue
  nmap <F8> <Plug>VimspectorStepOver
  nmap <F7> <Plug>VimspectorStepInto
  nmap <F20> <Plug>VimspectorStepOut
  nmap <F21> <Plug>VimspectorRunToCursor

  nmap <F10> <Plug>VimspectorToggleBreakpoint
  nmap <F22> <Plug>VimspectorToggleConditionalBreakpoint

  nmap <leader>rx :call vimspector#Reset()<cr>
  ]])
  vim.g.vimspector_install_gadgets = {'debugpy'}
end

return M
