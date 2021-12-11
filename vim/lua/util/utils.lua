local M = {}

function M.selected_text()
    return ""
end

function M.save_position()
  vim.cmd("mark `")
  -- save cursor position
  M.column_move = vim.fn.getpos('.')[3] - 1
end

function M.goto_saved_position()
  vim.cmd("normal ``")
  vim.cmd("normal 0" .. M.column_move .. "l")
end

  -- vmap <leader>h :lua print(require("util.utils").selected_text())<cr>
return M
