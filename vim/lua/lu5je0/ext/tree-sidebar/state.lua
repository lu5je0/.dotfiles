local Stack = require('lu5je0.lang.stack')

local M = {}

M.win = nil
M.buf = nil
M.width = 33
M.last_width = nil
M.active_tab_idx = 1

M.tab_cursors = { {1, 0}, {1, 0}, {1, 0} }

M.pwd_stack = Stack:create()
M.pwd_forward_stack = Stack:create()
M._is_jumping = false
M._last_pushed_cwd = nil

M.files = {
  root = nil,
  display_items = {},
  hide_dotfiles = true,
  git_status_map = {},
}

M.git_changes = {
  sections = {},
  display_items = {},
}

M.buffers = {
  display_items = {},
}

function M.is_open()
  return M.win ~= nil and vim.api.nvim_win_is_valid(M.win)
end

function M.is_buf_valid()
  return M.buf ~= nil and vim.api.nvim_buf_is_valid(M.buf)
end

function M.pwd_stack_push()
  if M._is_jumping then
    return
  end
  local cwd = vim.fn.getcwd()
  if M._last_pushed_cwd ~= cwd then
    M.pwd_stack:push(cwd)
    M._last_pushed_cwd = cwd
  end
end

function M.init_pwd_stack()
  local cwd = vim.fn.getcwd()
  M.pwd_stack:push(cwd)
  M._last_pushed_cwd = cwd
end

return M
