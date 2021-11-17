local M = {}

function M.setup()
  vim.cmd [[
    let g:Lf_StlSeparator = { 'left': '', 'right': '' }
    let g:Lf_WindowPosition = 'popup'
    let g:Lf_ShortcutF = "<leader>ff"
    let g:Lf_CommandMap = {'<C-J>': ['<DOWN>'], '<C-K>': ['<UP>']}
    let g:Lf_ShortcutB = ""
    let g:Lf_PreviewInPopup = 1

    let g:Lf_WildIgnore = {
      \ 'dir': ['.svn','.git','.hg'],
      \ 'file': ['*.sw?','~$*','*.bak','*.exe','*.o','*.so','*.py[co]']
      \}

    let g:Lf_PopupHeight = 0.7
  ]]
  vim.cmd('silent! unmap <leader>f')
end

function M.visual_leaderf(lf_cmd)
  vim.cmd(":Leaderf " .. lf_cmd .. " --input " .. vim.call('visual#visual_selection'))
end

return M
