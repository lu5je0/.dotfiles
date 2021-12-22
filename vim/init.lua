require('impatient')
require('enhance')
require('plugins')
require('commands')

vim.cmd[[
runtime settings.vim

if has("gui")
    runtime gvim.vim
endif

runtime functions.vim
runtime mappings.vim
runtime misc.vim
runtime runner.vim
runtime autocmd.vim
if has("mac")
    runtime im.vim
endif
]]

local function load_plug()
  if vim.fn.has("mac") then
    vim.g.python3_host_prog = '/usr/local/bin/python3'
  end
  if vim.fn.has("wsl") then
    vim.cmd("silent! PackerLoad im-switcher.nvim")
  end
  vim.cmd[[
  silent! PackerLoad vim-textobj-parameter
  silent! PackerLoad indent-blankline.nvim
  silent! PackerLoad nvim-lspconfig
  silent! PackerLoad nvim-cmp
  silent! PackerLoad nvim-autopairs
  silent! PackerLoad null-ls.nvim
  ]]
  vim.o.clipboard='unnamed'
end

vim.defer_fn(load_plug, 0)
