local M  = {}

function M.get_cursor_node()
  return vim.api.nvim_eval("fern#helper#new().sync.get_cursor_node()['_path']")
end

function M.preview_toggle()
  require("core/plugins_helper").load_plugin("fern-preview.vim")
  vim.call('fern_preview#toggle')
end

return M
