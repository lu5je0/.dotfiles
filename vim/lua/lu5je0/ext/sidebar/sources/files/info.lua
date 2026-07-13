-- File info popup ('K' on a file, shared by files tab and fs-edit).
local state = require('lu5je0.ext.sidebar.state')

local M = {}

local function format_size(size)
  if size < 1024 then return size .. ' B' end
  if size < 1024 * 1024 then return string.format('%.1f KB', size / 1024) end
  if size < 1024 * 1024 * 1024 then return string.format('%.1f MB', size / (1024 * 1024)) end
  return string.format('%.1f GB', size / (1024 * 1024 * 1024))
end

-- Build the info popup lines for a path. `lstat` is used first so symlinks are
-- reported as links (not silently followed like fs_stat does).
function M.build_info_lines(abs_path)
  local lstat = vim.uv.fs_lstat(abs_path)
  if not lstat then return nil end

  local name = vim.fn.fnamemodify(abs_path, ':t')
  local is_link = lstat.type == 'link'

  local lines = {
    '  Name:         ' .. name,
    '  Path:         ' .. abs_path,
    '  Type:         ' .. (is_link and 'symlink' or (lstat.type or 'unknown')),
  }

  if is_link then
    local target = vim.uv.fs_readlink(abs_path)
    lines[#lines + 1] = '  Link:         ' .. (target or '?')
    local tstat = vim.uv.fs_stat(abs_path)
    if tstat then
      lines[#lines + 1] = '  Target Type:  ' .. (tstat.type or 'unknown')
      lines[#lines + 1] = '  Target Size:  ' .. format_size(tstat.size)
    else
      lines[#lines + 1] = '  Target:       broken'
    end
  else
    lines[#lines + 1] = '  Size:         ' .. format_size(lstat.size)
  end

  lines[#lines + 1] = '  Permissions:  ' .. string.format('%o', lstat.mode % 4096)
  lines[#lines + 1] = '  Created:      ' .. os.date('%Y-%m-%d %H:%M:%S', lstat.birthtime.sec)
  lines[#lines + 1] = '  Modified:     ' .. os.date('%Y-%m-%d %H:%M:%S', lstat.mtime.sec)
  lines[#lines + 1] = '  Accessed:     ' .. os.date('%Y-%m-%d %H:%M:%S', lstat.atime.sec)

  return lines
end

-- Show the info popup for `abs_path`, anchored near `opts.line` in `opts.win`
-- and auto-closing on cursor movement in `opts.buf`.
function M.show_for_path(abs_path, opts)
  opts = opts or {}
  local win = opts.win or state.win
  local buf = opts.buf or state.buf
  local line = opts.line or vim.api.nvim_win_get_cursor(win)[1]

  local lines = M.build_info_lines(abs_path)
  if not lines then
    vim.notify('Cannot stat: ' .. abs_path, vim.log.levels.WARN)
    return
  end

  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[popup_buf].buftype = 'nofile'
  vim.bo[popup_buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
  vim.bo[popup_buf].modifiable = false

  local win_width = 0
  for _, l in ipairs(lines) do
    win_width = math.max(win_width, vim.fn.strdisplaywidth(l))
  end
  win_width = win_width + 2
  local win_height = #lines

  local cursor_row = vim.fn.screenpos(win, line, 1).row
  local anchor, popup_row
  if cursor_row - 1 - win_height - 2 >= 0 then
    anchor = 'SW'
    popup_row = cursor_row - 1
  else
    anchor = 'NW'
    popup_row = cursor_row
  end

  local anchor_col = vim.api.nvim_win_get_position(win)[2]
  local winid = vim.api.nvim_open_win(popup_buf, false, {
    relative = 'editor',
    anchor = anchor,
    row = popup_row,
    col = anchor_col,
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
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
    end,
  })
end

function M.show()
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.files.display_items[line]
  if not item or not item.node then return end

  M.show_for_path(item.node.abs_path, { win = state.win, buf = state.buf, line = line })
end

return M
