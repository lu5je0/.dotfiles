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
      vim.cmd('set signcolumn=auto')
      vim.cmd('silent! syntax clear')
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

local update_select_mode = false
vim.api.nvim_create_autocmd('ModeChanged', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    local mode = vim.api.nvim_get_mode().mode
    if mode == 's' then
      if vim.fn.has('wsl') == 1 then
        vim.cmd('hi Visual guibg=#D1D3CB guifg=#242424')
      else
        vim.cmd('hi Visual guibg=#ead6ac guifg=#242424')
      end
      update_select_mode = true
    elseif mode == 'v' or mode == 'n' then
      if update_select_mode then
        vim.cmd('hi Visual guibg=#3b3e48 guifg=none')
        update_select_mode = false
      end
    end
  end,
})

return M
