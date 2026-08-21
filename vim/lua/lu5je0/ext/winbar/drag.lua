local M = {}

local state = require('lu5je0.ext.winbar.state')
local util = require('lu5je0.ext.winbar.util')

local function copy(list)
  local r = {}
  for i, v in ipairs(list or {}) do r[i] = v end
  return r
end

local function listed(list)
  local r = {}
  for _, b in ipairs(list or {}) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then r[#r + 1] = b end
  end
  return r
end

local function index_of(list, buf)
  for i, b in ipairs(list) do
    if b == buf then return i end
  end
end

local function without(list, buf)
  local r = {}
  for _, b in ipairs(list) do
    if b ~= buf then r[#r + 1] = b end
  end
  return r
end

-- start a drag session, snapshotting the tab layout so every subsequent event is
-- applied from the original state instead of accumulating mutations.
function M.begin(buf, win)
  local snapshot = {}
  for w, list in pairs(state.win_bufs) do
    snapshot[w] = copy(list)
  end
  state.pending_close_win = nil
  state.drag = {
    buf = buf,
    win = win,
    snapshot = snapshot,
    order = copy(state.buf_order),
  }
end

-- resolve the drop index under a mouse column for the given window's winbar.
-- returns nil when that window has no rendered tabs.
local function drop_index(win, col)
  local regions = state.tab_regions[win]
  if not regions or #regions == 0 then return nil end
  for _, r in ipairs(regions) do
    if col >= r.from and col <= r.to then return r.ordinal end
  end
  if col < regions[1].from then return regions[1].ordinal end
  return regions[#regions].ordinal + 1
end

local function snapshot_of(drag, win)
  local snap = drag.snapshot[win]
  if snap then return listed(snap) end
  local cur = listed(state.win_bufs[win])
  if #cur > 0 then return cur end
  if vim.api.nvim_win_is_valid(win) then
    local b = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then return { b } end
  end
  return {}
end

local function insert_at(list, buf, ordinal)
  ordinal = math.max(1, math.min(#list + 1, ordinal or (#list + 1)))
  table.insert(list, ordinal, buf)
  return list
end

-- recompute the layout for the current drop target from the drag snapshot.
local function apply(drag, target_win, ordinal)
  local origin, buf = drag.win, drag.buf

  -- single normal window in a single tabpage: pure reorder of the global order
  if util.is_single_context(origin) and target_win == origin then
    local list = without(listed(drag.order), buf)
    state.buf_order = insert_at(list, buf, ordinal)
    state.pending_close_win = nil
    return
  end

  local origin_snap = snapshot_of(drag, origin)
  local origin_idx = index_of(origin_snap, buf) or 1
  local new_origin = without(origin_snap, buf)

  if target_win == origin then
    state.win_bufs[origin] = insert_at(new_origin, buf, ordinal)
    state.pending_close_win = nil
  else
    state.win_bufs[origin] = new_origin
    state.win_bufs[target_win] = insert_at(without(snapshot_of(drag, target_win), buf), buf, ordinal)

    if #new_origin == 0 and #vim.api.nvim_tabpage_list_wins(0) > 1 then
      state.pending_close_win = origin
    else
      state.pending_close_win = nil
      if vim.api.nvim_win_is_valid(origin) and vim.api.nvim_win_get_buf(origin) == buf then
        local fallback = new_origin[math.min(origin_idx, #new_origin)]
        if fallback then pcall(vim.api.nvim_win_set_buf, origin, fallback) end
      end
    end
  end

  if vim.api.nvim_win_is_valid(target_win) and vim.api.nvim_win_get_buf(target_win) ~= buf then
    pcall(vim.api.nvim_win_set_buf, target_win, buf)
  end
  if target_win ~= vim.api.nvim_get_current_win() then
    pcall(vim.api.nvim_set_current_win, target_win)
  end
end

-- close the window whose last tab was dragged away (deferred until release).
local function close_pending()
  local win = state.pending_close_win
  state.pending_close_win = nil
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  if #vim.api.nvim_tabpage_list_wins(0) <= 1 then return end

  local remaining = state.win_bufs[win]
  if remaining and #remaining > 0 then return end

  state.win_bufs[win] = nil
  state.tab_regions[win] = nil
  pcall(vim.api.nvim_win_close, win, false)
end

-- resolve the window + drop index currently under the mouse, or nil.
local function mouse_target(drag)
  local mp = vim.fn.getmousepos()
  local win = mp.winid
  if win == 0 or not vim.api.nvim_win_is_valid(win) then return end
  if win ~= drag.win and not util.is_normal_win(win) then return end
  if state.pending_close_win == win then
    return win, 1
  end
  return win, drop_index(win, mp.wincol)
end

-- runs on vim.schedule so buffer/window mutation happens outside expr context.
function M.on_drag()
  local drag = state.drag
  if not drag then return end
  local win, ordinal = mouse_target(drag)
  if not win then return end

  apply(drag, win, ordinal)
  vim.cmd('redrawstatus!')
end

-- release: apply the final position, then close a window left without tabs.
function M.finish_drag(drag)
  local win, ordinal = mouse_target(drag)
  if win then apply(drag, win, ordinal) end
  close_pending()
  vim.cmd('redrawstatus!')
end

-- expr <LeftDrag>: consume + reorder while a session is active, otherwise fall
-- through so normal mouse text-selection still works.
function M.left_drag()
  if state.drag then
    vim.schedule(M.on_drag)
    return ''
  end
  return '<LeftDrag>'
end

-- expr <LeftRelease>: finalise the drag, or fall through.
function M.left_release()
  local drag = state.drag
  if not drag then return '<LeftRelease>' end
  state.drag = nil
  vim.schedule(function() M.finish_drag(drag) end)
  return ''
end

return M
