local state = require('lu5je0.ext.tree-sidebar.state')
local ui = require('lu5je0.core.ui')

local M = {}

local _preview_active = false
local _preview_autocmd = nil
local _preview_type = nil -- 'diff' or 'file'

-- Diff preview state
local _diff_win_left = nil
local _diff_win_right = nil
local _diff_buf_left = nil
local _diff_buf_right = nil

local function get_current_item()
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local items
  if state.active_tab_idx == 1 then
    items = state.files.display_items
  elseif state.active_tab_idx == 2 then
    items = state.git_changes.display_items
  elseif state.active_tab_idx == 3 then
    items = state.buffers.display_items
  end
  local item = items and items[line]
  if not item or not item.node then
    return nil
  end
  if item.node.type == 'directory' then
    return nil
  end
  return item
end

local function close_diff_preview()
  if _diff_win_left and vim.api.nvim_win_is_valid(_diff_win_left) then
    vim.api.nvim_win_close(_diff_win_left, true)
  end
  if _diff_win_right and vim.api.nvim_win_is_valid(_diff_win_right) then
    vim.api.nvim_win_close(_diff_win_right, true)
  end
  _diff_win_left = nil
  _diff_win_right = nil
  _diff_buf_left = nil
  _diff_buf_right = nil
end

local function show_diff_preview(item)
  local node = item.node
  local cwd = vim.fn.getcwd()
  local rel_path = node.abs_path:sub(#cwd + 2)
  local xy = node.xy or '  '

  local new_lines = {}
  if vim.fn.filereadable(node.abs_path) == 1 then
    new_lines = vim.fn.readfile(node.abs_path)
  end

  local function render_diff(old_lines)
    close_diff_preview()

    local total_width = math.floor(vim.o.columns * 0.85)
    local half_width = math.floor(total_width / 2)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col_left = math.floor((vim.o.columns - total_width) / 2)
    local col_right = col_left + half_width

    local ft = vim.filetype.match({ filename = node.abs_path }) or ''

    _diff_buf_left = vim.api.nvim_create_buf(false, true)
    vim.bo[_diff_buf_left].buftype = 'nofile'
    vim.bo[_diff_buf_left].bufhidden = 'wipe'
    if ft ~= '' then vim.bo[_diff_buf_left].filetype = ft end
    vim.api.nvim_buf_set_lines(_diff_buf_left, 0, -1, false, old_lines)
    vim.bo[_diff_buf_left].modifiable = false

    _diff_buf_right = vim.api.nvim_create_buf(false, true)
    vim.bo[_diff_buf_right].buftype = 'nofile'
    vim.bo[_diff_buf_right].bufhidden = 'wipe'
    if ft ~= '' then vim.bo[_diff_buf_right].filetype = ft end
    vim.api.nvim_buf_set_lines(_diff_buf_right, 0, -1, false, new_lines)
    vim.bo[_diff_buf_right].modifiable = false

    _diff_win_left = vim.api.nvim_open_win(_diff_buf_left, false, {
      relative = 'editor',
      row = row,
      col = col_left,
      width = half_width,
      height = height,
      style = 'minimal',
      border = 'rounded',
      title = ' HEAD ',
      title_pos = 'center',
    })
    vim.wo[_diff_win_left].diff = true
    vim.wo[_diff_win_left].scrollbind = true
    vim.wo[_diff_win_left].wrap = false
    vim.wo[_diff_win_left].foldmethod = 'diff'
    vim.wo[_diff_win_left].foldlevel = 99
    vim.wo[_diff_win_left].cursorline = true

    _diff_win_right = vim.api.nvim_open_win(_diff_buf_right, false, {
      relative = 'editor',
      row = row,
      col = col_right,
      width = half_width,
      height = height,
      style = 'minimal',
      border = 'rounded',
      title = ' Working Tree ',
      title_pos = 'center',
    })
    vim.wo[_diff_win_right].diff = true
    vim.wo[_diff_win_right].scrollbind = true
    vim.wo[_diff_win_right].wrap = false
    vim.wo[_diff_win_right].foldmethod = 'diff'
    vim.wo[_diff_win_right].foldlevel = 99
    vim.wo[_diff_win_right].cursorline = true
  end

  if xy == '??' then
    render_diff({})
  else
    vim.system({ 'git', 'show', 'HEAD:' .. rel_path }, { text = true, cwd = cwd }, function(result)
      vim.schedule(function()
        local old_lines = {}
        if result.code == 0 and result.stdout then
          old_lines = vim.split(result.stdout, '\n', { plain = true })
          if #old_lines > 0 and old_lines[#old_lines] == '' then
            table.remove(old_lines)
          end
        end
        render_diff(old_lines)
      end)
    end)
  end
end

local function update_preview()
  if not _preview_active then
    return
  end
  local item = get_current_item()
  if not item then
    return
  end
  if state.active_tab_idx == 2 then
    show_diff_preview(item)
  else
    ui.preview(item.node.abs_path)
  end
end

local function stop_preview()
  _preview_active = false
  if _preview_autocmd then
    pcall(vim.api.nvim_del_autocmd, _preview_autocmd)
    _preview_autocmd = nil
  end
  if _preview_type == 'diff' then
    close_diff_preview()
  else
    ui.close_current_popup()
  end
  _preview_type = nil
end

local function start_preview()
  local item = get_current_item()
  if not item then
    return
  end
  _preview_active = true

  if state.active_tab_idx == 2 then
    _preview_type = 'diff'
    show_diff_preview(item)
  else
    _preview_type = 'file'
    ui.preview(item.node.abs_path)
  end

  _preview_autocmd = vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = state.buf,
    callback = function()
      if not _preview_active or not state:is_open() then
        stop_preview()
        return
      end
      update_preview()
    end,
  })
end

function M.toggle()
  if not state:is_open() then
    return
  end
  if _preview_active then
    stop_preview()
  else
    start_preview()
  end
end

function M.scroll_down()
  if not _preview_active then
    return
  end
  if _preview_type == 'diff' then
    if _diff_win_left and vim.api.nvim_win_is_valid(_diff_win_left) then
      vim.api.nvim_win_call(_diff_win_left, function()
        vim.cmd('normal! \\<C-d>')
      end)
    end
  else
    local popup = ui.current_popup
    if popup and popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      vim.api.nvim_win_call(popup.winid, function()
        vim.cmd('normal! \\<C-d>')
      end)
    end
  end
end

function M.scroll_up()
  if not _preview_active then
    return
  end
  if _preview_type == 'diff' then
    if _diff_win_left and vim.api.nvim_win_is_valid(_diff_win_left) then
      vim.api.nvim_win_call(_diff_win_left, function()
        vim.cmd('normal! \\<C-u>')
      end)
    end
  else
    local popup = ui.current_popup
    if popup and popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      vim.api.nvim_win_call(popup.winid, function()
        vim.cmd('normal! \\<C-u>')
      end)
    end
  end
end

return M
