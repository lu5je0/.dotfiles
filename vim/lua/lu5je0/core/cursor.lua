local M = {}

function M.wapper_fn_for_solid_guicursor(fn)
  return function(...)
  local guicursor_backup = vim.o.guicursor
    vim.o.guicursor=''
    fn(...)
    vim.o.guicursor = guicursor_backup
  end
end

function M.save_position()
  M.cursor_position = vim.fn.getpos('.')
end

function M.goto_saved_position()
  vim.fn.cursor { M.cursor_position[2], M.cursor_position[3] }
end

local guicursor_backup = vim.o.guicursor
function M.cursor_visible(option)
  if option then
    vim.o.guicursor = guicursor_backup
    vim.cmd('hi Cursor blend=NONE')
  else
    vim.cmd [[
    hi Cursor blend=100
    set guicursor+=a:Cursor/lCursor
    ]]
  end
end

return M
