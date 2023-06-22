local M = {}

local function read_lines_from_file(file_path)
  local lines = {}
  for line in io.lines(file_path) do
    table.insert(lines, line)
  end
  return lines
end

M.current_popup = nil

function M.close_current_popup()
  if M.current_popup ~= nil then
    M.current_popup:unmount()
    M.current_popup = nil
  end
end

function M.preview(file_path)
  M.close_current_popup()

  local Popup = require('nui.popup')
  local event = require('nui.utils.autocmd').event

  local popup_options = {
    enter = false,
    border = {
      style = 'single',
      highlight = 'Fg',
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
  M.current_popup = popup
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave"}, {
    pattern = '*',
    once = true,
    callback = function()
      M.close_current_popup()
    end,
  })

  popup:mount()

  local buf_id = vim.api.nvim_win_get_buf(popup.winid)
  local lines = read_lines_from_file(file_path)
  vim.api.nvim_buf_set_lines(buf_id, 0, #lines, false, lines)
  vim.wo[popup.winid].number = true
  local ft, _ = vim.filetype.match(({ filename = file_path }))
  if not ft then
    ft, _ = vim.filetype.match(({ buf = buf_id }))
  end
  vim.bo[buf_id].filetype = ft or ''
  vim.wo[popup.winid].signcolumn = 'no'
  vim.bo[vim.fn.winbufnr(popup.winid)].buflisted = false
  vim.api.nvim_win_set_cursor(popup.winid, { 1, 0 })

  -- unmount component when cursor leaves buffer
  popup:on(event.BufLeave, function()
    popup:unmount()
  end)

  popup:map('n', '<esc>', function()
    popup:unmount()
  end, { noremap = true })
  
  return popup
end

-- M.popup_info_window = function(content)
--   -- 关闭上一个弹窗
--   if _G.preview_popup ~= nil then
--     _G.preview_popup:unmount()
--   end
--
--   local Popup = require('nui.popup')
--   local event = require('nui.utils.autocmd').event
--
--   local content_array = content:split('\n')
--
--   local width = 0
--   for _, line in ipairs(content_array) do
--     width = math.max(width, #line)
--   end
--
--   local popup_options = {
--     enter = false,
--     border = {
--       style = 'rounded',
--       highlight = 'FloatBorder',
--       text = {
--         top_align = 'left',
--       },
--     },
--     highlight = 'Normal:Normal',
--     position = {
--       row = 1,
--       col = 1,
--     },
--     relative = 'cursor',
--     size = {
--       width = width,
--       height = #content_array,
--     },
--     opacity = 1,
--     zindex = 100,
--     -- focusable = false,
--   }
--
--   local popup = Popup(popup_options)
--   _G.preview_popup = popup
--   vim.cmd('au! CursorMoved,CursorMovedI,InsertEnter,BufLeave * ++once lua _G.preview_popup:unmount()')
--
--   popup:mount()
--
--   vim.fn.win_execute(popup.winid, 'set ft=popup')
--   vim.api.nvim_buf_set_lines(popup.bufnr, 0, 0, false, content_array)
--   vim.bo[vim.fn.winbufnr(popup.winid)].modifiable = false
--   vim.bo[vim.fn.winbufnr(popup.winid)].readonly = true
--
--   -- unmount component when cursor leaves buffer
--   popup:on(event.BufLeave, function()
--     popup:unmount()
--   end)
--
--   popup:map('n', '<esc>', function()
--     popup:unmount()
--   end, { noremap = true })
-- end

return M
