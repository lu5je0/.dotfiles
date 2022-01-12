local M = {}

function M.save_position()
  M.cursor_position = vim.fn.getpos(".")
end

function M.goto_saved_position()
  vim.fn.cursor({M.cursor_position[2], M.cursor_position[3]})
end

return M
