local M = {}

M.feedkey = function(key, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), mode, true)
end

function M.selected_text()
    return ""
end

function M.is_register_contains_newline(register)
  local s = vim.fn.getreg(register)
  return string.find(s, '\n') ~= nil
end

function M.save_position()
  M.cursor_position = vim.fn.getpos(".")
end

function M.goto_saved_position()
  vim.fn.cursor({M.cursor_position[2], M.cursor_position[3]})
end

  -- vmap <leader>h :lua print(require("util.utils").selected_text())<cr>
return M
