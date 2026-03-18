vim.bo.tabstop=2
vim.bo.shiftwidth=2
vim.bo.softtabstop=2

vim.keymap.set('n', 'yp', function()
  vim.cmd("JsonCopyPath")
end, { buffer = true })
