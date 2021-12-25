local M = {}

M.preview = function(file_path)
  if _G.preview_popup ~= nil then
    _G.preview_popup:unmount()
  end

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
    position = '50%',
    size = {
      width = '70%',
      height = '80%',
    },
    relative = 'editor',
    opacity = 1,
    zindex = 100,
    -- focusable = false,
  }

  local popup = Popup(popup_options)
  _G.preview_popup = popup
  vim.cmd('au! CursorMoved,CursorMovedI,InsertEnter,BufLeave * ++once lua _G.preview_popup:unmount()')

  popup:mount()

  vim.fn.win_execute(popup.winid, 'setlocal signcolumn=no')
  vim.fn.win_execute(popup.winid, 'setlocal number')
  vim.fn.win_execute(popup.winid, 'e ' .. file_path)
  vim.api.nvim_buf_set_option(vim.fn.winbufnr(popup.winid), 'buflisted', false)

  -- unmount component when cursor leaves buffer
  popup:on(event.BufLeave, function()
    popup:unmount()
  end)

  popup:map('n', '<esc>', function()
    popup:unmount()
  end, { noremap = true })
end

M.popup_info_window = function(content)
  if _G.preview_popup ~= nil then
    _G.preview_popup:unmount()
  end

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
      col = 1,
    },
    relative = 'cursor',
    size = {
      width = #content,
      height = 1,
    },
    opacity = 1,
    zindex = 100,
    -- focusable = false,
  }

  local popup = Popup(popup_options)
  _G.preview_popup = popup
  vim.cmd('au! CursorMoved,CursorMovedI,InsertEnter,BufLeave * ++once lua _G.preview_popup:unmount()')

  popup:mount()

  vim.fn.win_execute(popup.winid, 'set ft=popup')
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
end

return M
