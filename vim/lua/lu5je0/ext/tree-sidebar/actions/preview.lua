local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local ui = require('lu5je0.core.ui')
local diff_preview = require('lu5je0.ext.tree-sidebar.actions.diff_preview')

local M = {}

-- Preview state lives in per-tab state.preview so two tabpages don't
-- share the active flag, autocmd handles, or preview type.
local function pv()
  return state.preview
end

local function get_current_item()
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local items
  if state.active_tab_idx == config.tab_idx('files') then
    items = state.files.display_items
  elseif state.active_tab_idx == config.tab_idx('git_changes') then
    items = state.git_changes.display_items
  elseif state.active_tab_idx == config.tab_idx('buffers') then
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
  local p = pv()
  if p.autocmd then
    pcall(vim.api.nvim_del_autocmd, p.autocmd)
    p.autocmd = nil
  end
  if p.bufleave_autocmd then
    pcall(vim.api.nvim_del_autocmd, p.bufleave_autocmd)
    p.bufleave_autocmd = nil
  end
end

local function stop_preview()
  local p = pv()
  p.active = false
  clear_autocmds()
  diff_preview.close()
  ui.close_current_popup()
  p.type = nil
end

local function update_preview()
  local p = pv()
  if not p.active then
    return
  end
  local item = get_current_item()
  if not item then
    return
  end
  if state.active_tab_idx == config.tab_idx('git_changes') then
    diff_preview.show(item, function(new_type)
      p.type = new_type
      if new_type == nil then
        p.active = false
        clear_autocmds()
      end
    end)
  else
    ui.preview(item.node.abs_path)
  end
end

local function setup_autocmds()
  local p = pv()
  p.autocmd = vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = state.buf,
    once = true,
    callback = function()
      stop_preview()
    end,
  })

  p.bufleave_autocmd = vim.api.nvim_create_autocmd('BufLeave', {
    buffer = state.buf,
    once = true,
    callback = function()
      vim.schedule(function()
        local cur_win = vim.api.nvim_get_current_win()
        local dp_state = state.diff_preview
        if cur_win == dp_state.win_left or cur_win == dp_state.win_right then
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
  local p = pv()
  p.active = true

  if state.active_tab_idx == config.tab_idx('git_changes') then
    p.type = 'diff'
    diff_preview.show(item, function(new_type)
      p.type = new_type
      if new_type == nil then
        p.active = false
        clear_autocmds()
      end
    end)
  else
    p.type = 'file'
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

  local p = pv()
  p.active = false
  clear_autocmds()

  vim.keymap.set('n', 'q', function()
    ui.close_current_popup()
    p.type = nil
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
  pv().active = false
  clear_autocmds()

  local dp_state = state.diff_preview
  if dp_state.win_left and vim.api.nvim_win_is_valid(dp_state.win_left) then
    vim.api.nvim_set_current_win(dp_state.win_left)
  elseif dp_state.win_right and vim.api.nvim_win_is_valid(dp_state.win_right) then
    vim.api.nvim_set_current_win(dp_state.win_right)
  end
end

function M.is_active()
  return pv().active
end

function M.stop()
  stop_preview()
end

function M.toggle()
  if not state:is_open() then
    return
  end
  local p = pv()
  if p.active then
    if p.type == 'diff' then
      enter_diff_window()
    else
      enter_file_preview_window()
    end
  else
    start_preview()
  end
end

function M.scroll_down()
  local p = pv()
  if not p.active then
    return
  end
  if p.type == 'diff' then
    local dwin = state.diff_preview.win_left
    if dwin and vim.api.nvim_win_is_valid(dwin) then
      vim.api.nvim_win_call(dwin, function()
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
  local p = pv()
  if not p.active then
    return
  end
  if p.type == 'diff' then
    local dwin = state.diff_preview.win_left
    if dwin and vim.api.nvim_win_is_valid(dwin) then
      vim.api.nvim_win_call(dwin, function()
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
