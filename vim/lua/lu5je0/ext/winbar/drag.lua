local M = {}

local state = require('lu5je0.ext.winbar.state')
local util = require('lu5je0.ext.winbar.util')

-- move `buf` to `target` ordinal within the window's logical buffer list,
-- persisting the new order to the right backing store.
local function move(win, buf, target)
  local list = util.get_buf_list(win)
  local from
  for i, b in ipairs(list) do
    if b == buf then from = i; break end
  end
  if not from then return false end

  target = math.max(1, math.min(#list, target))
  if from == target then return false end

  table.remove(list, from)
  table.insert(list, target, buf)
  util.persist_order(win, list)
  return true
end

-- resolve the ordinal under a mouse column for the given window's winbar.
local function target_ordinal(win, col)
  local regions = state.tab_regions[win]
  if not regions or #regions == 0 then return nil end
  for _, r in ipairs(regions) do
    if col >= r.from and col <= r.to then return r.ordinal end
  end
  -- past either edge: clamp to the first / last visible tab
  if col < regions[1].from then return regions[1].ordinal end
  return regions[#regions].ordinal
end

local function neighbor_of(list, buf)
  for i, b in ipairs(list) do
    if b == buf then return list[i + 1] or list[i - 1] end
  end
end

-- move `buf` out of `source_win` and into `target_win` at `target` ordinal.
-- the target window switches to display the moved buffer. the source window
-- falls back to a neighbouring buffer, or — when the moved tab was its last one
-- — is only marked for closing, so it keeps an empty tab strip until release.
local function move_to_window(source_win, target_win, buf, target)
  if source_win == target_win then return false end

  local src = util.get_buf_list(source_win)
  local neighbor = neighbor_of(src, buf)
  local new_src = {}
  for _, b in ipairs(src) do
    if b ~= buf then new_src[#new_src + 1] = b end
  end
  util.persist_order(source_win, new_src)

  if vim.api.nvim_win_is_valid(source_win)
    and vim.api.nvim_win_get_buf(source_win) == buf
  then
    if neighbor and vim.api.nvim_buf_is_valid(neighbor) then
      pcall(vim.api.nvim_win_set_buf, source_win, neighbor)
    elseif #vim.api.nvim_tabpage_list_wins(0) > 1 then
      -- last tab dragged out: defer the close to release, leaving an empty strip
      state.pending_close_win = source_win
    end
  end

  local tgt = state.win_bufs[target_win] or {}
  local filtered = {}
  for _, b in ipairs(tgt) do
    if b ~= buf and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
      filtered[#filtered + 1] = b
    end
  end
  target = math.max(1, math.min(#filtered + 1, target or (#filtered + 1)))
  table.insert(filtered, target, buf)
  state.win_bufs[target_win] = filtered

  -- dragged back into the window that was pending close: cancel it
  if state.pending_close_win == target_win then
    state.pending_close_win = nil
  end

  pcall(vim.api.nvim_win_set_buf, target_win, buf)
  return true
end

-- close the window whose last tab was dragged away (deferred until release).
local function close_pending()
  local win = state.pending_close_win
  state.pending_close_win = nil
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  if #vim.api.nvim_tabpage_list_wins(0) <= 1 then return false end

  local remaining = state.win_bufs[win]
  if remaining and #remaining > 0 then return false end

  state.win_bufs[win] = nil
  state.tab_regions[win] = nil
  pcall(vim.api.nvim_win_close, win, false)
  return true
end

-- runs on vim.schedule so buffer/window mutation happens outside expr context.
-- reorders within the hovered window, or moves the buffer live into another
-- window the moment the mouse crosses into it.
function M.on_drag()
  local drag = state.drag
  if not drag then return end
  local mp = vim.fn.getmousepos()
  local win = mp.winid
  if win == 0 then return end

  if win == drag.win then
    local target = target_ordinal(win, mp.wincol)
    if target and move(win, drag.buf, target) then
      vim.cmd('redrawstatus!')
    end
    return
  end

  if not vim.api.nvim_win_is_valid(win) or not util.is_normal_win(win) then return end

  local ordinal = target_ordinal(win, mp.wincol)
  if not ordinal then
    local list = state.win_bufs[win]
    ordinal = (list and #list or 0) + 1
  end

  if move_to_window(drag.win, win, drag.buf, ordinal) then
    drag.win = win
    pcall(vim.api.nvim_set_current_win, win)
    vim.cmd('redrawstatus!')
  end
end

-- release phase: commit any not-yet-applied cross-window move, then close the
-- window whose last tab was dragged away.
function M.finish_drag(drag)
  local mp = vim.fn.getmousepos()
  local tgt = mp.winid

  if tgt ~= 0 and tgt ~= drag.win
    and vim.api.nvim_win_is_valid(tgt) and util.is_normal_win(tgt)
  then
    local ordinal = target_ordinal(tgt, mp.wincol)
    if not ordinal then
      local list = state.win_bufs[tgt]
      ordinal = (list and #list or 0) + 1
    end
    if move_to_window(drag.win, tgt, drag.buf, ordinal) then
      pcall(vim.api.nvim_set_current_win, tgt)
    end
  end

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

-- expr <LeftRelease>: finalise the drag (possibly cross-window), or fall through.
function M.left_release()
  local drag = state.drag
  if not drag then return '<LeftRelease>' end
  state.drag = nil
  vim.schedule(function() M.finish_drag(drag) end)
  return ''
end

return M
