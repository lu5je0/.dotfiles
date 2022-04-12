if not pcall(require, 'impatient') then
  vim.notify('impatient fail')
end
require('plugins')
require('enhance')
require('commands')
require('patch')
require('mappings')
require('autocmds')
require('filetype')

vim.cmd([[
runtime settings.vim
runtime functions.vim
runtime mappings.vim
runtime misc.vim
runtime autocmd.vim
if has("mac")
  runtime im.vim
endif
]])

local defer_plugins = {
  'nvim-tree.lua',
  'nvim-cmp',
  'nvim-lspconfig',
  'nvim-autopairs',
  'null-ls.nvim',
  'LeaderF',
  'toggleterm.nvim',
  'Comment.nvim',
}

if vim.fn.has('wsl') == 1 then
  table.insert(defer_plugins, 'im-switcher.nvim')
end

for _, plugin in ipairs(defer_plugins) do
  vim.schedule(function()
    vim.cmd('PackerLoad ' .. plugin)
  end)
end

vim.defer_fn(function()
  vim.o.clipboard = 'unnamedplus'
  vim.cmd('packadd matchit')
end, 10)
