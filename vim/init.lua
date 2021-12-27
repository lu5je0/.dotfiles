require('impatient')
require('enhance')
require('plugins')
require('commands')

vim.cmd([[
runtime settings.vim
runtime functions.vim
runtime mappings.vim
runtime misc.vim
runtime runner.vim
runtime autocmd.vim
if has("mac")
  runtime im.vim
endif
]])

local function load_plug()
  if vim.fn.has('mac') == 1 then
    vim.g.python3_host_prog = '/usr/local/bin/python3'
  end

  local plugins = {
    'indent-blankline.nvim',
    'vim-textobj-parameter',
    'nvim-lspconfig',
    'nvim-cmp',
    'nvim-autopairs',
    'null-ls.nvim',
  }

  if vim.fn.has('wsl') == 1 then
    table.insert(plugins, 'im-switcher.nvim')
  end

  require('packer').loader(unpack(plugins))
  vim.o.clipboard = 'unnamed'
end

vim.defer_fn(load_plug, 0)
