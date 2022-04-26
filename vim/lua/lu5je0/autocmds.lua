local M = {}

M.default_group = vim.api.nvim_create_augroup('l_main_autocmd_group', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    vim.cmd('set formatoptions-=o')
  end,
})

vim.api.nvim_create_autocmd('BufWinEnter', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    if vim.fn.line2byte(vim.fn.line('$') + 1) > 1024 * 1024 * 3 then
      vim.cmd('syntax clear')
      vim.cmd("echom 'syntax cleared on large file'")
    end
  end,
})

vim.api.nvim_create_autocmd('BufReadPost', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    if vim.fn.line("'\"") > 0 and vim.fn.line("'\"") <= vim.fn.line("$") then
      if vim.bo.filetype == 'gitcommit' then
        return
      end
      vim.fn.setpos('.', vim.fn.getpos("'\""))
    end
  end
})

vim.api.nvim_create_autocmd('TextYankPost', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    vim.highlight.on_yank({ higroup="Visual", timeout = 300 })
  end
})

return M
