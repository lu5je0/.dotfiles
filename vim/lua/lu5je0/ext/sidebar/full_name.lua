-- Floating popup that extends an overflowing sidebar line while preserving
-- the sidebar's text origin and horizontal viewport.
local state = require('lu5je0.ext.sidebar.state')

local M = {}

function M.setup()
  local popup_win = nil
  local popup_buf = nil
  local ns_id = require('lu5je0.ext.sidebar.view').ns_id()
  local popup_ns = vim.api.nvim_create_namespace('sidebar_fullname')

  local function hide_popup()
    if popup_win and vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_close(popup_win, true)
    end
    popup_win = nil
  end

  local function get_or_create_buf()
    if popup_buf and vim.api.nvim_buf_is_valid(popup_buf) then
      return popup_buf
    end
    popup_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[popup_buf].buftype = 'nofile'
    vim.bo[popup_buf].bufhidden = 'hide'
    return popup_buf
  end

  local function show_popup()
    if not state:is_open() then
      hide_popup()
      return
    end
    local win = state.win
    if vim.api.nvim_get_current_win() ~= win then
      hide_popup()
      return
    end

    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_nr = cursor[1]
    local line = vim.fn.getline(line_nr)
    local text_width = vim.fn.strdisplaywidth(line)
    local win_info = vim.fn.getwininfo(win)
    local textoff = (win_info[1] and win_info[1].textoff) or 0
    local leftcol = (win_info[1] and win_info[1].leftcol) or 0
    local win_width = vim.api.nvim_win_get_width(win) - textoff
    local visible_width = text_width - leftcol

    if visible_width <= win_width then
      hide_popup()
      return
    end

    local buf = get_or_create_buf()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, popup_ns, 0, -1)
    local extmarks = vim.api.nvim_buf_get_extmarks(state.buf, ns_id, { line_nr - 1, 0 }, { line_nr - 1, -1 }, { details = true })
    for _, extmark in ipairs(extmarks) do
      local row = extmark[2]
      local col = extmark[3]
      local details = extmark[4]
      if type(details) == 'table' and details.hl_group then
        local end_col
        if not details.end_col or (details.end_row and details.end_row ~= row) then
          end_col = -1
        else
          end_col = details.end_col
        end
        vim.api.nvim_buf_add_highlight(buf, popup_ns, details.hl_group, 0, col, end_col)
      end
    end

    local topline = vim.fn.line('w0', win)
    local win_config = {
      relative = 'win',
      win = win,
      row = line_nr - topline,
      col = textoff,
      width = math.min(visible_width, vim.o.columns - win_info[1].wincol + 1 - textoff),
      height = 1,
      noautocmd = true,
      style = 'minimal',
      zindex = 40,
      border = 'none',
    }

    if popup_win and vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_set_config(popup_win, win_config)
      vim.api.nvim_win_set_buf(popup_win, buf)
    else
      popup_win = vim.api.nvim_open_win(buf, false, win_config)
      vim.wo[popup_win].cursorline = true
      vim.wo[popup_win].cursorlineopt = 'line'
      vim.wo[popup_win].wrap = false
      vim.wo[popup_win].sidescrolloff = 0
    end

    -- Search and horizontal movement can scroll the sidebar. Keep the same
    -- viewport so the popup's name, icon and highlights stay on the same cells.
    vim.api.nvim_win_call(popup_win, function()
      vim.fn.winrestview({ lnum = 1, col = cursor[2], leftcol = leftcol, topline = 1 })
    end)
  end

  local group = vim.api.nvim_create_augroup('sidebar-fullname', { clear = true })

  vim.api.nvim_create_autocmd('CursorMoved', {
    group = group,
    callback = function()
      if not state:is_open() or vim.api.nvim_get_current_win() ~= state.win then
        hide_popup()
        return
      end
      show_popup()
    end,
  })

  vim.api.nvim_create_autocmd('WinScrolled', {
    group = group,
    callback = function()
      if not state:is_open() or vim.api.nvim_get_current_win() ~= state.win then
        return
      end
      show_popup()
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave', 'WinClosed' }, {
    group = group,
    callback = function()
      hide_popup()
    end,
  })
end

return M
