local state = require('lu5je0.ext.tree-sidebar.state')
local ui = require('lu5je0.core.ui')
local diff_preview = require('lu5je0.ext.tree-sidebar.actions.diff_preview')

local M = {}

local _preview_active = false
local _preview_autocmd = nil
local _preview_bufleave_autocmd = nil
local _preview_type = nil -- 'diff' or 'file'

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

local function clear_autocmds()
  if _preview_autocmd then
    pcall(vim.api.nvim_del_autocmd, _preview_autocmd)
    _preview_autocmd = nil
  end
  if _preview_bufleave_autocmd then
    pcall(vim.api.nvim_del_autocmd, _preview_bufleave_autocmd)
    _preview_bufleave_autocmd = nil
  end
end

local function stop_preview()
  _preview_active = false
  clear_autocmds()
  diff_preview.close()
  ui.close_current_popup()
  _preview_type = nil
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
    diff_preview.show(item, function(new_type)
      _preview_type = new_type
      if new_type == nil then
        _preview_active = false
        clear_autocmds()
      end
    end)
  else
    ui.preview(item.node.abs_path)
  end
end

local function setup_autocmds()
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

  _preview_bufleave_autocmd = vim.api.nvim_create_autocmd('BufLeave', {
    buffer = state.buf,
    once = true,
    callback = function()
      vim.schedule(function()
        local cur_win = vim.api.nvim_get_current_win()
        if cur_win == diff_preview.win_left or cur_win == diff_preview.win_right then
          return
        end
        local popup = ui.current_popup
        if popup and popup.winid and cur_win == popup.winid then
          return
        end
        stop_preview()
      end)
    end,
  })
end

local function start_preview()
  local item = get_current_item()
  if not item then
    return
  end
  _preview_active = true

  if state.active_tab_idx == 2 then
    _preview_type = 'diff'
    diff_preview.show(item, function(new_type)
      _preview_type = new_type
      if new_type == nil then
        _preview_active = false
        clear_autocmds()
      end
    end)
  else
    _preview_type = 'file'
    ui.preview(item.node.abs_path)
  end

  setup_autocmds()
end

local function enter_file_preview_window()
  local popup = ui.current_popup
  local buf = ui.get_preview_buf()
  if not popup or not popup.winid or not vim.api.nvim_win_is_valid(popup.winid) or not buf then
    return
  end

  _preview_active = false
  clear_autocmds()

  vim.keymap.set('n', 'q', function()
    ui.close_current_popup()
    _preview_type = nil
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
  end, { buffer = buf, nowait = true, silent = true })

  if ui.current_popup_autocmd then
    pcall(vim.api.nvim_del_autocmd, ui.current_popup_autocmd)
    ui.current_popup_autocmd = nil
  end

  vim.api.nvim_win_set_config(popup.winid, { focusable = true })
  vim.api.nvim_set_current_win(popup.winid)
end

local function enter_diff_window()
  _preview_active = false
  clear_autocmds()

  if diff_preview.win_left and vim.api.nvim_win_is_valid(diff_preview.win_left) then
    vim.api.nvim_set_current_win(diff_preview.win_left)
  elseif diff_preview.win_right and vim.api.nvim_win_is_valid(diff_preview.win_right) then
    vim.api.nvim_set_current_win(diff_preview.win_right)
  end
end

function M.is_active()
  return _preview_active
end

function M.stop()
  stop_preview()
end

function M.toggle()
  if not state:is_open() then
    return
  end
  if _preview_active then
    if _preview_type == 'diff' then
      enter_diff_window()
    else
      enter_file_preview_window()
    end
  else
    start_preview()
  end
end

function M.scroll_down()
  if not _preview_active then
    return
  end
  if _preview_type == 'diff' then
    if diff_preview.win_left and vim.api.nvim_win_is_valid(diff_preview.win_left) then
      vim.api.nvim_win_call(diff_preview.win_left, function()
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
    if diff_preview.win_left and vim.api.nvim_win_is_valid(diff_preview.win_left) then
      vim.api.nvim_win_call(diff_preview.win_left, function()
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
