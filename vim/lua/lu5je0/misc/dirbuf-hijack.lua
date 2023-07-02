local M = {}

local function hijack_directory(path)
  if vim.fn.isdirectory(path) == 0 then
    return
  end
  
  vim.cmd('Dirbuf .')
end

function M.setup()
  local group = vim.api.nvim_create_augroup('dir-buf-hijack', { clear = true })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    pattern = { '*' },
    callback = function(arg)
      if arg.file == '' then
        return
      end
      vim.cmd("autocmd! dir-buf-hijack")
      hijack_directory(arg.file)
    end
  })
end

return M
