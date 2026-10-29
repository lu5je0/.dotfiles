local state = require('lu5je0.ext.sidebar.state')
local config = require('lu5je0.ext.sidebar.config')
local ui = require('lu5je0.core.ui')
local diff_preview = require('lu5je0.ext.sidebar.actions.diff_preview')
local text_preview = require('lu5je0.ext.sidebar.actions.text_preview')

local M = {}
local enter_preview_window

-- Preview state lives in per-tab state.preview so two tabpages don't
-- share the active flag, autocmd handles, or preview type.
local function pv()
  return state.preview
end

local function get_current_item()
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local source = require('lu5je0.ext.sidebar.tabs').get_active_source()
  if source and source.preview_item then return source.preview_item() end
  local tab = config.tabs[state.active_tab_idx]
  local source_state = tab and state[tab.id]
  local items = source_state and source_state.display_items
  local item = items and items[line]
  if not item or not item.node then
    return nil
  end
  if item.node.type == 'directory' then
    return nil
  end
  return item
end

local function clear_autocmds(p)
  p = p or pv()
  if p.autocmd then
    pcall(vim.api.nvim_del_autocmd, p.autocmd)
    p.autocmd = nil
  end
  if p.bufleave_autocmd then
    pcall(vim.api.nvim_del_autocmd, p.bufleave_autocmd)
    p.bufleave_autocmd = nil
  end
end

local function stop_preview(ts)
  ts = ts or state.tab()
  local p = ts.preview
  p.active = false
  p.enter_pending = false
  clear_autocmds(p)
  diff_preview.close(ts)
  text_preview.close(ts)
  if ts == state.tab() then ui.close_current_popup() end
  p.type = nil
end

local function show_text(item, p)
  p.type = 'text'
  text_preview.show(item, function()
    p.active, p.type = false, nil
    clear_autocmds(p)
  end)
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
  if item.preview_kind == 'text' then
    show_text(item, p)
  elseif require('lu5je0.ext.sidebar.tabs').get_active_source().preview_kind == 'diff' then
    diff_preview.show(item, function(new_type)
      p.type = new_type
      if new_type == 'diff' and p.enter_pending then
        vim.schedule(function()
          if p == pv() and p.active and p.enter_pending then enter_preview_window() end
        end)
      end
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
    callback = function()
      if require('lu5je0.ext.sidebar.tabs').get_active_source().preview_kind == 'diff' then
        stop_preview()
      else
        update_preview()
      end
    end,
  })

  p.bufleave_autocmd = vim.api.nvim_create_autocmd('BufLeave', {
    buffer = state.buf,
    once = true,
    callback = function()
      vim.schedule(function()
        local cur_win = vim.api.nvim_get_current_win()
        if cur_win == p.text_win then return end
        local dp_state = state.diff_preview
        if cur_win == dp_state.win_left or cur_win == dp_state.win_right or cur_win == dp_state.win_single then
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

  if item.preview_kind == 'text' then
    show_text(item, p)
  elseif require('lu5je0.ext.sidebar.tabs').get_active_source().preview_kind == 'diff' then
    p.type = 'diff'
    diff_preview.show(item, function(new_type)
      p.type = new_type
      if new_type == 'diff' and p.enter_pending then
        vim.schedule(function()
          if p == pv() and p.active and p.enter_pending then enter_preview_window() end
        end)
      end
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

enter_preview_window = function()
  local d = state.diff_preview
  local win = pv().type == 'text' and pv().text_win or (d.win_single or d.win_left or d.win_right)
  if not win or not vim.api.nvim_win_is_valid(win) then
    pv().enter_pending = true
    return
  end
  pv().enter_pending = false
  pv().active = false
  clear_autocmds()
  vim.api.nvim_set_current_win(win)
end

function M.is_active()
  return pv().active
end

function M.stop()
  stop_preview()
end

M.stop_for = stop_preview

function M.refresh()
  if diff_preview.refresh() then
    return
  end
  if pv().active then
    update_preview()
  end
end

function M.toggle()
  if not state:is_open() then
    return
  end
  local p = pv()
  if p.active then
    if p.type == 'diff' or p.type == 'text' then
      enter_preview_window()
    else
      stop_preview()
    end
  else
    start_preview()
  end
end

function M.enter()
  if not state:is_open() then return end
  if not pv().active then start_preview() end
  if pv().active and (pv().type == 'diff' or pv().type == 'text') then enter_preview_window() end
end

function M.scroll_down()
  local p = pv()
  if not p.active then
    return
  end
  if p.type == 'diff' then
    local dp_state = state.diff_preview
    local dwin = (dp_state.win_single and vim.api.nvim_win_is_valid(dp_state.win_single)) and dp_state.win_single
      or dp_state.win_left
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
    local dp_state = state.diff_preview
    local dwin = (dp_state.win_single and vim.api.nvim_win_is_valid(dp_state.win_single)) and dp_state.win_single
      or dp_state.win_left
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
