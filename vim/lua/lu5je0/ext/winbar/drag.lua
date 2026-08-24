local M = {}

local state = require('lu5je0.ext.winbar.state')
local util = require('lu5je0.ext.winbar.util')

local function anim()
  return require('lu5je0.ext.winbar.anim')
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

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
-- applied from the original state instead of accumulating mutations. `mouse_col`
-- lets us record where within the grabbed tab the cursor sits, so the tab does
-- not jump under the cursor when it starts following.
function M.begin(buf, win, mouse_col)
  local snapshot = {}
  for w, list in pairs(state.win_bufs) do
    snapshot[w] = copy(list)
  end
  state.pending_close_win = nil

  local grab_offset = 0
  local regions = state.tab_regions[win]
  if regions and mouse_col then
    for _, r in ipairs(regions) do
      if r.buf == buf then grab_offset = mouse_col - r.from; break end
    end
  end

  state.drag = {
    buf = buf,
    win = win,
    snapshot = snapshot,
    order = copy(state.buf_order),
    grab_offset = grab_offset,
  }
  anim().seed(win)
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
-- returns 'reorder' when the drop stays within the origin window, else 'cross'.
local function apply(drag, target_win, ordinal)
  local origin, buf = drag.win, drag.buf

  -- single normal window in a single tabpage: pure reorder of the global order
  if util.is_single_context(origin) and target_win == origin then
    local list = without(listed(drag.order), buf)
    state.buf_order = insert_at(list, buf, ordinal)
    state.pending_close_win = nil
    return 'reorder'
  end

  local origin_snap = snapshot_of(drag, origin)
  local origin_idx = index_of(origin_snap, buf) or 1
  local new_origin = without(origin_snap, buf)

  if target_win == origin then
    state.win_bufs[origin] = insert_at(new_origin, buf, ordinal)
    state.pending_close_win = nil
    return 'reorder'
  end

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

  if vim.api.nvim_win_is_valid(target_win) and vim.api.nvim_win_get_buf(target_win) ~= buf then
    pcall(vim.api.nvim_win_set_buf, target_win, buf)
  end
  if target_win ~= vim.api.nvim_get_current_win() then
    pcall(vim.api.nvim_set_current_win, target_win)
  end
  return 'cross'
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

-- Floating column + drop ordinal for a drag inside its own window, derived from
-- the live (truncation-aware) layout. Returns nil when the grabbed tab has no
-- visible placement, in which case the caller falls back to an instant reorder.
--
-- Swap rule: the grabbed tab's centre landing inside another tab's span is
-- exactly ">50% overlap" for equal-width tabs.
local function follow_target(drag, win, mouse_col)
  local layout = require('lu5je0.ext.winbar.render').layout(win)
  if not layout or #layout.tabs == 0 then return nil end

  local dragged
  for _, t in ipairs(layout.tabs) do
    if t.buf == drag.buf then dragged = t; break end
  end
  if not dragged then return nil end

  local W = dragged.width
  local first, last = layout.tabs[1], layout.tabs[#layout.tabs]
  local min_left = first.col
  local max_left = math.max(min_left, last.col + last.width - W)
  local float_left = clamp(mouse_col - (drag.grab_offset or 0), min_left, max_left)

  local centre = float_left + math.floor(W / 2)
  local ordinal = first.ordinal
  for _, t in ipairs(layout.tabs) do
    if centre >= t.col and centre <= t.col + t.width - 1 then
      ordinal = t.ordinal
      break
    elseif centre > t.col + t.width - 1 then
      ordinal = t.ordinal
    end
  end

  return float_left, ordinal
end

-- runs on vim.schedule so buffer/window mutation happens outside expr context.
-- `drag.win` stays the snapshot origin; `drag.host` is the window the grabbed
-- tab currently lives in, and that is what gets the follow animation.
function M.on_drag()
  local drag = state.drag
  if not drag then return end
  local mp = vim.fn.getmousepos()
  local win = mp.winid
  if win == 0 or not vim.api.nvim_win_is_valid(win) then return end
  if win ~= drag.win and not util.is_normal_win(win) then return end

  -- drop index: from the layout once the tab lives here, else by span hit-test
  local float_left, ordinal = follow_target(drag, win, mp.wincol)
  if not ordinal then
    ordinal = (state.pending_close_win == win) and 1 or drop_index(win, mp.wincol)
  end
  if not ordinal then return end

  apply(drag, win, ordinal)

  local prev_host = drag.host or drag.win
  drag.host = win

  -- after apply the tab lives in `win`, so its float column is resolvable
  local settled_left = select(1, follow_target(drag, win, mp.wincol)) or float_left
  if not (settled_left and anim().follow(win, drag.buf, settled_left)) then
    anim().clear(win)
  end
  if prev_host ~= win then
    -- close the gap left behind, unless that window is going away entirely
    if state.pending_close_win == prev_host then
      anim().clear(prev_host)
    else
      anim().reflow(prev_host)
    end
  end

  vim.cmd('redrawstatus!')
end

-- release: settle the grabbed tab into its slot, then close an emptied window.
function M.finish_drag(drag)
  local mp = vim.fn.getmousepos()
  local win = mp.winid
  local host = drag.host or drag.win
  local settling = false

  if win ~= 0 and vim.api.nvim_win_is_valid(win)
    and (win == drag.win or util.is_normal_win(win))
  then
    local float_left, ordinal = follow_target(drag, win, mp.wincol)
    if not ordinal then
      ordinal = (state.pending_close_win == win) and 1 or drop_index(win, mp.wincol)
    end
    if ordinal then
      apply(drag, win, ordinal)
      if float_left or follow_target(drag, win, mp.wincol) then
        anim().release(win)
        settling = true
      else
        anim().clear(win)
      end
      if host ~= win and state.pending_close_win ~= host then anim().reflow(host) end
    end
  end

  close_pending()
  if not settling then vim.cmd('redrawstatus!') end
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
