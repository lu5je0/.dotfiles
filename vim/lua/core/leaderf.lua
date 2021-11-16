local M = {}

function M.setup()
  vim.g.Lf_StlSeparator = {
    left = '',
    right = ''
  }

  vim.g.Lf_WindowPosition = 'popup'

  vim.g.Lf_CommandMap = {
    ['<C-J>'] = {'<DOWN>'},
    ['<C-K>'] = {'<UP>'}
  }

  vim.g.Lf_ShortcutF = "<leader>ff"
  vim.g.Lf_ShortcutB = ""
  vim.g.Lf_PreviewInPopup = 1
  vim.g.Lf_PopupHeight = 0.7
  vim.g.Lf_WildIgnore = {
     dir = {'.svn','.git','.hg'},
     file = {'*.sw?','~$*','*.bak','*.exe','*.o','*.so','*.py[co]'}
    }

  vim.cmd('silent! unmap <leader>f')
end

function M.visual_leaderf(lf_cmd)
  local search = vim.call('visual#visual_selection')
  search = string.gsub(search, "'", "")
  search = string.gsub(search, "\n", "")

  vim.cmd(":Leaderf " .. lf_cmd .. " --input '" .. search .. "'")
end

return M
