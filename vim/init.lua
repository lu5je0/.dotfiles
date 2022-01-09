require('impatient')
require('enhance')
require('plugins')
require('commands')

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

local function load_plug()
  local plugins = {
    'indent-blankline.nvim',
    'nvim-cmp',
    'nvim-lspconfig',
    'nvim-autopairs',
    'null-ls.nvim',
  }

  if vim.fn.has('wsl') == 1 then
    table.insert(plugins, 'im-switcher.nvim')
  end

  require('packer').loader(unpack(plugins))
  vim.o.clipboard = 'unnamedplus'
end

vim.defer_fn(load_plug, 0)

vim.cmd("let g:markdown_folding = 1")
