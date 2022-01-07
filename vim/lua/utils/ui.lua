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

  vim.wo[popup.winid].number = true
  vim.wo[popup.winid].signcolumn = 'no'
  vim.fn.win_execute(popup.winid, 'e ' .. file_path)
  vim.bo[vim.fn.winbufnr(popup.winid)].buflisted = false

  -- unmount component when cursor leaves buffer
  popup:on(event.BufLeave, function()
    popup:unmount()
  end)

  popup:map('n', '<esc>', function()
    popup:unmount()
  end, { noremap = true })
end

M.popup_info_window = function(content)
  -- 关闭上一个弹窗
  if _G.preview_popup ~= nil then
    _G.preview_popup:unmount()
  end

  local Popup = require('nui.popup')
  local event = require('nui.utils.autocmd').event

  local content_array = content:split('\n')

  local width = 0
  for _, line in ipairs(content_array) do
    width = math.max(width, #line)
  end

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
      width = width,
      height = #content_array,
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
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 0, false, content_array)
  vim.bo[vim.fn.winbufnr(popup.winid)].modifiable = false
  vim.bo[vim.fn.winbufnr(popup.winid)].readonly = true

  -- unmount component when cursor leaves buffer
  popup:on(event.BufLeave, function()
    popup:unmount()
  end)

  popup:map('n', '<esc>', function()
    popup:unmount()
  end, { noremap = true })
end

return M
