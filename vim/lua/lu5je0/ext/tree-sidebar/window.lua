local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')

local M = {}

function M.create_buf()
  if state:is_buf_valid() then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = config.filetype
  vim.bo[buf].modifiable = false
  state.buf = buf
  return buf
end

function M.open()
  if state:is_open() then
    return
  end

  local buf = M.create_buf()

  vim.cmd('topleft vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, state.width)

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'auto'
  vim.wo[win].foldcolumn = '1'
  vim.wo[win].cursorline = true
  vim.wo[win].cursorlineopt = 'line'
  vim.wo[win].wrap = false
  vim.wo[win].list = false
  vim.wo[win].winfixwidth = true

  state.win = win
end

function M.close()
  if not state:is_open() then
    return
  end
  state.width = vim.api.nvim_win_get_width(state.win)
  vim.api.nvim_win_close(state.win, true)
  state.win = nil
end

function M.toggle(opts)
  opts = opts or {}
  if state:is_open() then
    M.close()
  else
    M.open()
    if not opts.focus then
      vim.cmd('wincmd p')
    end
  end
end

function M.focus()
  if not state:is_open() then
    M.open()
  end
  vim.api.nvim_set_current_win(state.win)
end

function M.toggle_width()
  if not state:is_open() then
    return
  end
  local cur_width = vim.api.nvim_win_get_width(state.win)
  local half = math.floor(vim.o.columns * 0.5)

  if state.last_width == nil or cur_width ~= half then
    state.last_width = cur_width
    vim.api.nvim_win_set_width(state.win, half)
  else
    vim.api.nvim_win_set_width(state.win, state.last_width)
  end
  state.width = vim.api.nvim_win_get_width(state.win)
end

function M.setup_remember_width()
  vim.api.nvim_create_autocmd('WinClosed', {
    callback = function(args)
      if vim.bo[args.buf].filetype ~= config.filetype then
        return
      end
      if state:is_open() then
        state.width = vim.api.nvim_win_get_width(state.win)
      end
    end,
  })
end

function M.setup_guicursor()
  local guicursor_backup = nil

  local function set_replace_cursor_block(guicursor)
    local parts = vim.split(guicursor, ',', { trimempty = true })
    local replaced = false
    for i, part in ipairs(parts) do
      local mode_list = vim.split(vim.split(part, ':', { plain = true })[1] or '', '-', { trimempty = true })
      for _, mode in ipairs(mode_list) do
        if mode == 'r' or mode == 'cr' or mode == 'o' then
          parts[i] = 'r-cr-o:block'
          replaced = true
          break
        end
      end
    end
    if not replaced then
      table.insert(parts, 'r-cr-o:block')
    end
    return table.concat(parts, ',')
  end

  local group = vim.api.nvim_create_augroup('tree-sidebar-guicursor', { clear = true })

  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype == config.filetype then
        if guicursor_backup == nil then
          guicursor_backup = vim.o.guicursor
          vim.o.guicursor = set_replace_cursor_block(vim.o.guicursor)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWinLeave', 'WinLeave' }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype == config.filetype then
        if guicursor_backup ~= nil then
          vim.o.guicursor = guicursor_backup
          guicursor_backup = nil
        end
      end
    end,
  })
end

function M.setup_full_name()
  local popup_win = nil
  local popup_buf = nil
  local ns_id = require('lu5je0.ext.tree-sidebar.render').ns_id()

  local function hide_popup()
    if popup_win and vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_close(popup_win, true)
    end
    popup_win = nil
    popup_buf = nil
  end

  local function show_popup()
    hide_popup()
    if not state:is_open() then
      return
    end
    local win = state.win
    if vim.api.nvim_get_current_win() ~= win then
      return
    end

    local line_nr = vim.api.nvim_win_get_cursor(win)[1]
    local line = vim.fn.getline(line_nr)
    local text_width = vim.fn.strdisplaywidth(line)
    local win_info = vim.fn.getwininfo(win)
    local textoff = (win_info[1] and win_info[1].textoff) or 0
    local win_width = vim.api.nvim_win_get_width(win) - textoff

    if text_width <= win_width then
      return
    end

    popup_buf = vim.api.nvim_create_buf(false, true)
    local padded_line = ' ' .. line
    vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, { padded_line })

    local extmarks = vim.api.nvim_buf_get_extmarks(state.buf, ns_id, { line_nr - 1, 0 }, { line_nr - 1, -1 }, { details = true })
    for _, extmark in ipairs(extmarks) do
      local col = extmark[3]
      local details = extmark[4]
      if type(details) == 'table' and details.hl_group then
        local end_col = details.end_col and (details.end_col + 1) or -1
        vim.api.nvim_buf_add_highlight(popup_buf, ns_id, details.hl_group, 0, col + 1, end_col)
      end
    end

    popup_win = vim.api.nvim_open_win(popup_buf, false, {
      relative = 'win',
      win = win,
      row = line_nr - 1,
      col = 0,
      width = math.min(text_width + 1, vim.o.columns - 2),
      height = 1,
      noautocmd = true,
      style = 'minimal',
      zindex = 40,
      border = 'none',
    })
    vim.wo[popup_win].cursorline = true
    vim.wo[popup_win].cursorlineopt = 'line'
  end

  local group = vim.api.nvim_create_augroup('tree-sidebar-fullname', { clear = true })

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

  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave', 'WinClosed' }, {
    group = group,
    callback = function()
      hide_popup()
    end,
  })
end

return M
