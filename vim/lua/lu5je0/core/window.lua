local M = {}

function M.effective_win_width()
  local win_width = vim.fn.winwidth(0)

  -- return zero if the window cannot be found
  local win_id = vim.fn.win_getid()

  if win_id == 0 then
    return win_width
  end

  -- if the window does not exist the result is an empty list
  local win_info = vim.fn.getwininfo(win_id)

  -- check if result table is empty
  if next(win_info) == nil then
    return win_width
  end

  return win_width - win_info[1].textoff
end

function M.is_cur_line_out_of_window()
  local line = vim.fn.getline(".")
  local text_width = vim.fn.strdisplaywidth(vim.fn.substitute(line, "[^[:print:]]*$", "", "g"))
  local win_width = M.effective_win_width()
  return text_width > win_width
end

return M
