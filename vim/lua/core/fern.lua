local M = {}

local plugins_helper = require('core/plugins_helper')

function M.get_cursor_node()
  return vim.api.nvim_eval("fern#helper#new().sync.get_cursor_node()['_path']")
end

function M.fern_toggle()
  plugins_helper.load_plugin('fern.vim')
  vim.cmd('Fern . -drawer -stay -toggle -keep')
end

function M.git_checkout_file()
  vim.cmd('!git checkout -- ' .. M.get_cursor_node())
  vim.cmd('normal r')
end

function M.git_reset_file()
  vim.cmd('!git reset -- ' .. M.get_cursor_node())
  vim.cmd('normal r')
end

function M.preview_toggle()
  plugins_helper.load_plugin('fern-preview.vim')
  vim.call('fern_preview#toggle')
end

return M
