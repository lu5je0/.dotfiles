local group = vim.api.nvim_create_augroup('l_main_autocmd_group', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = '*',
  callback = function()
    vim.cmd('set formatoptions-=o')
  end,
})

vim.api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  pattern = '*',
  callback = function()
    if vim.fn.line2byte(vim.fn.line('$') + 1) > 1024 * 1024 * 3 then
      vim.cmd('syntax clear')
      vim.cmd("echom 'syntax cleared on large file'")
    end
  end,
})
