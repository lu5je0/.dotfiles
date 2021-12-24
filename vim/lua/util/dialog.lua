local M = {}

M.dialog = function(content)
  local Popup = require('nui.popup')
  local event = require('nui.utils.autocmd').event

  local popup_options = {
    enter = false,
    border = {
      style = 'rounded',
      highlight = 'FloatBorder',
      text = {
        top_align = 'left',
      },
    },
    highlight = 'Normal:Normal',
    position = {
      row = 1,
      col = 0,
    },
    relative = 'cursor',
    size = {
      width = 30,
      height = 3,
    },
    opacity = 1,
    zindex = 100,
    -- focusable = false,
  }

  local popup = Popup(popup_options)

  popup:mount()

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, { content })
  vim.api.nvim_buf_set_option(popup.bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(popup.bufnr, 'readonly', true)

  -- unmount component when cursor leaves buffer
  popup:on(event.BufLeave, function()
    popup:unmount()
  end)

  popup:map('n', '<esc>', function()
    popup:unmount()
  end, { noremap = true })

  -- vim.cmd('autocmd ++once CursorMoved')
end

M.dialog()

return M
