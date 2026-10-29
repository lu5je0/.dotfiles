local state = require('lu5je0.ext.sidebar.state')
local config = require('lu5je0.ext.sidebar.config')

local M = {}

M.max_visible = 3

function M.visible_indices(ts)
  ts = ts or state.tab()
  local indices = {}
  for i, tab in ipairs(config.tabs) do
    if not tab.transient or ts.visible_tabs[i] then indices[#indices + 1] = i end
  end
  return indices
end

function M.save_width()
  if not state:is_open() then return end
  local idx = state.active_tab_idx
  local width = vim.api.nvim_win_get_width(state.win)
  state.tab_widths[idx] = width
  if not config.tabs[idx].width then state.width = width end
end

function M.apply_width()
  if not state:is_open() then return end
  local idx = state.active_tab_idx
  local width = state.tab_widths[idx] or config.tabs[idx].width or state.width
  vim.api.nvim_win_set_width(state.win, math.min(width, math.floor(vim.o.columns * 0.6)))
end

function M.reset_transient(ts)
  ts.visible_tabs = {}
  if config.tabs[ts.active_tab_idx].transient then ts.active_tab_idx = 1 end
  ts._visible_start = 1
end

local function ensure_visible(idx)
  local start = state._visible_start or 1
  if idx < start then
    state._visible_start = idx
  elseif idx > start + M.max_visible - 1 then
    state._visible_start = idx - M.max_visible + 1
  end
end

function M.render_winbar()
  if not state:is_open() then
    return
  end

  local indices = M.visible_indices()
  local position = 1
  for i, idx in ipairs(indices) do if idx == state.active_tab_idx then position = i end end
  ensure_visible(position)

  local tab_count = #indices
  local visible_count = math.min(M.max_visible, tab_count)
  local visible_start = state._visible_start or 1
  local visible_end = math.min(visible_start + visible_count - 1, tab_count)

  local win_width = vim.api.nvim_win_get_width(state.win)
  local base_width = math.floor(win_width / visible_count)
  local remainder = win_width - base_width * visible_count

  local parts = {}
  local vi = 0
  for i = visible_start, visible_end do
    vi = vi + 1
    local idx = indices[i]
    local tab = config.tabs[idx]
    local hl = (idx == state.active_tab_idx) and '%#SidebarTabActive#' or '%#SidebarTabInactive#'
    local cell_width = base_width + (vi <= remainder and 1 or 0)
    local content_width = cell_width - 1
    local label = tab.label
    local label_width = vim.fn.strdisplaywidth(label)

    if label_width > content_width then
      local max_w = content_width - 1
      local char_count = vim.fn.strchars(label)
      local truncated = ''
      local w = 0
      for ci = 0, char_count - 1 do
        local ch = vim.fn.strcharpart(label, ci, 1)
        local ch_w = vim.fn.strdisplaywidth(ch)
        if w + ch_w > max_w then
          break
        end
        truncated = truncated .. ch
        w = w + ch_w
      end
      label = truncated .. '…'
      label_width = vim.fn.strdisplaywidth(label)
    end

    local right_pad = content_width - label_width
    local click = string.format('%%@v:lua.require\'lu5je0.ext.sidebar.tabs\'._click_%d@', idx)
    parts[#parts + 1] = click .. hl .. ' ' .. label .. string.rep(' ', right_pad) .. '%X'
  end
  vim.wo[state.win].winbar = table.concat(parts)
end

function M.save_view()
  if state:is_open() then
    vim.api.nvim_win_call(state.win, function()
      state.tab_cursors[state.active_tab_idx] = vim.fn.winsaveview()
    end)
  end
end

function M.restore_view(idx)
  if not state:is_open() then return end
  local saved = state.tab_cursors[idx]
  if saved and saved.lnum then
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    local view = vim.tbl_extend('force', {}, saved)
    view.lnum = math.min(view.lnum, line_count)
    view.topline = math.min(view.topline or 1, line_count)
    vim.api.nvim_win_call(state.win, function()
      vim.fn.winrestview(view)
    end)
  end
end

function M.set_active_tab(idx)
  state.visible_tabs[idx] = true
  if idx == state.active_tab_idx then
    return false
  end
  M.save_view()
  M.save_width()
  require('lu5je0.ext.sidebar.source_base').deactivate(state.tab())
  state.active_tab_idx = idx
  M.apply_width()
  M.render_winbar()
  return true
end

function M.switch_to(idx)
  if idx < 1 or idx > #config.tabs then
    return
  end
  if not M.set_active_tab(idx) then
    return
  end

  local source = M.get_active_source()
  if source and source.render then
    source.render()
  end

  M.restore_view(idx)

  local keymaps = require('lu5je0.ext.sidebar.keymaps')
  keymaps.apply_for_tab(idx)
  require('lu5je0.ext.sidebar.watcher').refresh()
end

local function cycle(direction)
  local indices = M.visible_indices()
  for position, idx in ipairs(indices) do
    if idx == state.active_tab_idx then M.switch_to(indices[(position - 1 + direction) % #indices + 1]); return end
  end
end
function M.next_tab() cycle(1) end
function M.prev_tab() cycle(-1) end

function M.get_active_source()
  local tab = config.tabs[state.active_tab_idx]
  if not tab then
    return nil
  end
  local ok, source = pcall(require, 'lu5je0.ext.sidebar.sources.' .. tab.id)
  if ok then
    return source
  end
  vim.notify('sidebar: failed to load source ' .. tab.id .. ': ' .. tostring(source), vim.log.levels.WARN)
  return nil
end

for i = 1, #config.tabs do
  M['_click_' .. i] = function()
    M.switch_to(i)
  end
end

return M
