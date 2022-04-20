local M = {}


M.boostrap = function()
  local group = vim.api.nvim_create_augroup('ime-status', { clear = true })
  local path = vim.fn.stdpath('config')
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      print(path .. '/lib/toDisableIME.exe')
      io.popen(path .. '/lib/toDisableIME.exe')
    end
  })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = { '*' },
    callback = function()
      io.popen(path .. '/lib/toEnableIME.exe')
    end
  })
end

return M
