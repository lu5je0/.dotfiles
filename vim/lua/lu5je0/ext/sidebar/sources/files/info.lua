-- File info popup ('K' on a file in the files tab).
local state = require('lu5je0.ext.sidebar.state')

local M = {}

local function format_size(size)
  if size < 1024 then return size .. ' B' end
  if size < 1024 * 1024 then return string.format('%.1f KB', size / 1024) end
  if size < 1024 * 1024 * 1024 then return string.format('%.1f MB', size / (1024 * 1024)) end
  return string.format('%.1f GB', size / (1024 * 1024 * 1024))
end

function M.show()
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.files.display_items[line]
  if not item or not item.node then return end

  local node = item.node
  local stat = vim.uv.fs_stat(node.abs_path)
  if not stat then
    vim.notify('Cannot stat: ' .. node.abs_path, vim.log.levels.WARN)
    return
  end

  local lines = {
    '  Name:         ' .. node.name,
    '  Path:         ' .. node.abs_path,
    '  Type:         ' .. (stat.type or 'unknown'),
    '  Size:         ' .. format_size(stat.size),
    '  Permissions:  ' .. string.format('%o', stat.mode % 4096),
    '  Created:      ' .. os.date('%Y-%m-%d %H:%M:%S', stat.birthtime.sec),
    '  Modified:     ' .. os.date('%Y-%m-%d %H:%M:%S', stat.mtime.sec),
    '  Accessed:     ' .. os.date('%Y-%m-%d %H:%M:%S', stat.atime.sec),
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win_width = 0
  for _, l in ipairs(lines) do
    win_width = math.max(win_width, vim.fn.strdisplaywidth(l))
  end
  win_width = win_width + 2
  local win_height = #lines

  local cursor_row = vim.fn.screenpos(state.win, line, 1).row
  local anchor, popup_row
  if cursor_row - 1 - win_height - 2 >= 0 then
    anchor = 'SW'
    popup_row = cursor_row - 1
  else
    anchor = 'NW'
    popup_row = cursor_row
  end

  local sidebar_col = vim.api.nvim_win_get_position(state.win)[2]
  local winid = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    anchor = anchor,
    row = popup_row,
    col = sidebar_col,
    width = win_width,
    height = win_height,
    style = 'minimal',
    border = 'rounded',
    title = ' File Info ',
    title_pos = 'center',
    focusable = false,
    zindex = 100,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave', 'InsertEnter' }, {
    buffer = state.buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
    end,
  })
end

return M
