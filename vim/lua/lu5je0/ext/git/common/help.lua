local M = {}

local help_win = nil
local help_buf = nil
local help_return_win = nil

local function close_help()
  local return_win = help_return_win
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    vim.api.nvim_win_close(help_win, true)
  end
  help_win = nil
  help_buf = nil
  help_return_win = nil
  if return_win and vim.api.nvim_win_is_valid(return_win) then
    vim.api.nvim_set_current_win(return_win)
  end
end

M.close_help = close_help

function M.show_help(title, help_lines)
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    close_help()
    return
  end

  help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].buftype = 'nofile'
  vim.bo[help_buf].bufhidden = 'wipe'
  vim.bo[help_buf].swapfile = false
  vim.bo[help_buf].filetype = 'help'

  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)
  vim.bo[help_buf].modifiable = false

  local log_win = vim.api.nvim_get_current_win()
  help_return_win = log_win
  local log_pos = vim.api.nvim_win_get_position(log_win)
  local log_height = vim.api.nvim_win_get_height(log_win)
  local log_width = vim.api.nvim_win_get_width(log_win)

  local win_width = 40
  local win_height = #help_lines + 2
  local col = log_pos[2] + math.floor((log_width - win_width) / 2)
  local row = log_pos[1] + math.floor((log_height - win_height) / 2)

  help_win = vim.api.nvim_open_win(help_buf, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = win_width,
    height = win_height,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
    zindex = 100,
  })
  vim.wo[help_win].winhighlight = 'Normal:Normal,FloatBorder:Special'

  local help_opts = { buffer = help_buf, nowait = true }
  vim.keymap.set('n', 'q', close_help, help_opts)
  vim.keymap.set('n', '<esc>', close_help, help_opts)
end

return M
