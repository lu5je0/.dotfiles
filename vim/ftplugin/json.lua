vim.cmd([[
setlocal tabstop=2
setlocal shiftwidth=2
setlocal softtabstop=2
]])

vim.keymap.set('n', 'yp', function()
  vim.cmd("JsonCopyPath")
end, {
  buffer = true
})
