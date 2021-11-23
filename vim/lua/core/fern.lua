local M  = {}

local plugins_helper = require("core/plugins_helper")

function M.get_cursor_node()
  return vim.api.nvim_eval("fern#helper#new().sync.get_cursor_node()['_path']")
end

function M.fern_toggle()
  plugins_helper.load_plugin("fern.vim")
  vim.cmd("Fern . -drawer -stay -toggle -keep")
end

function M.preview_toggle()
  plugins_helper.load_plugin("fern-preview.vim")
  vim.call('fern_preview#toggle')
end

return M
