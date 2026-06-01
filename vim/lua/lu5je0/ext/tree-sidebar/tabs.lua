local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')

local M = {}

function M.render_winbar()
  if not state:is_open() then
    return
  end

  local tab_count = #config.tabs
  local win_width = vim.api.nvim_win_get_width(state.win)
  local base_width = math.floor(win_width / tab_count)
  local remainder = win_width - base_width * tab_count

  local parts = {}
  for i, tab in ipairs(config.tabs) do
    local hl = (i == state.active_tab_idx) and '%#TreeSidebarTabActive#' or '%#TreeSidebarTabInactive#'
    local cell_width = base_width + (i <= remainder and 1 or 0)
    -- 1 space left padding
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
    local click = string.format('%%@v:lua.require\'lu5je0.ext.tree-sidebar.tabs\'._click_%d@', i)
    parts[#parts + 1] = click .. hl .. ' ' .. label .. string.rep(' ', right_pad) .. '%X'
  end
  vim.wo[state.win].winbar = table.concat(parts)
end

function M.switch_to(idx)
  if idx < 1 or idx > #config.tabs then
    return
  end
  if idx == state.active_tab_idx then
    return
  end

  if state:is_open() then
    local cursor = vim.api.nvim_win_get_cursor(state.win)
    state.tab_cursors[state.active_tab_idx] = cursor
  end

  state.active_tab_idx = idx
  M.render_winbar()

  local source = M.get_active_source()
  if source and source.render then
    source.render()
  end

  if state:is_open() then
    local saved = state.tab_cursors[idx]
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    local line = math.min(saved[1], line_count)
    pcall(vim.api.nvim_win_set_cursor, state.win, { math.max(1, line), saved[2] })
  end

  local keymaps = require('lu5je0.ext.tree-sidebar.keymaps')
  keymaps.apply_for_tab(idx)
end

function M.next_tab()
  local next_idx = state.active_tab_idx % #config.tabs + 1
  M.switch_to(next_idx)
end

function M.prev_tab()
  local prev_idx = (state.active_tab_idx - 2) % #config.tabs + 1
  M.switch_to(prev_idx)
end

function M.get_active_source()
  local tab = config.tabs[state.active_tab_idx]
  if not tab then
    return nil
  end
  local ok, source = pcall(require, 'lu5je0.ext.tree-sidebar.sources.' .. tab.id)
  if ok then
    return source
  end
  vim.notify('tree-sidebar: failed to load source ' .. tab.id .. ': ' .. tostring(source), vim.log.levels.WARN)
  return nil
end

for i = 1, #config.tabs do
  M['_click_' .. i] = function()
    M.switch_to(i)
  end
end

return M
