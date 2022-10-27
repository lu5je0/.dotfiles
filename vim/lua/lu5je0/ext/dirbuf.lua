require("dirbuf").setup {
  write_cmd = 'DirbufSync -confirm',
  sort_order = 'directories_first',
}
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('dirbuf', { clear = true }),
  pattern = 'dirbuf',
  callback = function()
    vim.keymap.set('n', '<leader>e', '<nop>', { buffer = true })
    vim.keymap.set('n', '<leader>fe', '<nop>', { buffer = true })
    vim.keymap.set('n', '<leader>q', function() vim.cmd('DirbufQuit') end, { buffer = true })
    vim.keymap.set('n', '<c-i>', '<Plug>(dirbuf_history_forward)', { buffer = true })
    vim.keymap.set('n', '<c-o>', '<Plug>(dirbuf_history_backward)', { buffer = true })
  end,
})
