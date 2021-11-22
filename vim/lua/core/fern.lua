local M  = {}

function M.get_cursor_node()
  return vim.api.nvim_eval("fern#helper#new().sync.get_cursor_node()['_path']")
end

return M
