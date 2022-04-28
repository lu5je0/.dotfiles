if not pcall(require, 'impatient') then
  vim.notify('impatient fail')
end
require('lu5je0.plugins')
require('lu5je0.enhance')
require('lu5je0.commands')
require('lu5je0.patch')
require('lu5je0.mappings')
require('lu5je0.autocmds')
require('lu5je0.filetype')

vim.cmd([[
runtime settings.vim
runtime functions.vim
runtime mappings.vim
runtime misc.vim
]])

if vim.fn.has('wsl') == 1 then
  require('lu5je0.misc.im.win.im').boostrap()
elseif vim.fn.has('mac') == 1 then
  vim.cmd('runtime mac_im.vim')
end

local delay = 0;
for _, plugin in ipairs(_G.defer_plugins) do
  vim.defer_fn(function()
    vim.cmd('PackerLoad ' .. plugin)
  end, delay)
  delay = delay + 10
end

vim.defer_fn(function()
  vim.o.clipboard = 'unnamedplus'
  vim.cmd('packadd matchit')
end, 10)
