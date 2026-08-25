-- Slide animation for winbar tab dragging. The grabbed tab follows the cursor
-- (its column tracks the mouse, no easing) while the other tabs ease aside to
-- open a gap; on release the grabbed tab eases into that gap.
--
-- Positions come from `render.layout`, the same truncation-aware placement the
-- static render uses, so this works whether or not the strip is truncated:
-- tabs scrolled out of view simply have no placement and are not painted, and
-- the `N ` / ` N` truncation markers are painted at their fixed columns.
--
-- Reordering itself is decided by the drag layer (>50% overlap); `state.tab_regions`
-- always holds the settled layout so hit-testing stays stable while visuals slide.
local M = {}

local canvas = require('lu5je0.ext.winbar.canvas')

local FILL = 'BufferLineFill'
local STEP_MS = 16
local EASE = 0.34   -- exponential ease-out factor per tick (non-grabbed tabs)
local SNAP = 0.5    -- within this many columns of target -> arrived

-- win -> {
--   tabs   = { [buf] = { cells, target, width } },
--   order  = { buf, ... },       -- paint order, grabbed last
--   pos    = { [buf] = column (float) },
--   markers = { { cells, col } },
--   dragged, float, floating, ncols,
-- }
local anims = {}
-- win -> { [buf] = column } : last settled columns, seed for the next drag
local last_pos = {}
local timer

local function render()
  return require('lu5je0.ext.winbar.render')
end

local function ensure_timer()
  if timer then return end
  timer = (vim.uv or vim.loop).new_timer()
  timer:start(STEP_MS, STEP_MS, vim.schedule_wrap(M.tick))
end

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

-- record the current settled layout as the seed positions for a drag
function M.seed(win)
  local layout = render().layout(win)
  if not layout then
    last_pos[win] = nil
    return
  end
  local pos = {}
  for _, t in ipairs(layout.tabs) do pos[t.buf] = t.col end
  last_pos[win] = pos
end

-- Build animation state for `win`. With `dragged` that tab is pinned to
-- `float_left` and painted on top; without it every tab just eases to its slot
-- (used for the window a tab was dragged out of, so its gap closes smoothly).
local function build(win, dragged, float_left)
  if not vim.api.nvim_win_is_valid(win) then return nil end
  local layout = render().layout(win)
  if not layout or #layout.tabs == 0 then return nil end

  local tabs, order = {}, {}
  local has_dragged = false
  for _, t in ipairs(layout.tabs) do
    tabs[t.buf] = { cells = canvas.parse(t.markup), target = t.col, width = t.width }
    if dragged and t.buf == dragged then
      has_dragged = true
    else
      order[#order + 1] = t.buf
    end
  end
  if dragged then
    -- grabbed tab has no visible placement here: nothing sensible to float
    if not has_dragged then return nil end
    order[#order + 1] = dragged -- painted last, on top
  end

  local markers = {}
  for _, mk in ipairs(layout.markers) do
    markers[#markers + 1] = { cells = canvas.parse(mk.markup), col = mk.col }
  end

  local prev = anims[win]
  local base = (prev and prev.pos) or last_pos[win] or {}

  -- When the truncation window scrolls, tabs appear that have no previous
  -- column; easing from stale columns would fling them across the strip. Ease
  -- only while every visible neighbour has a known position, else snap.
  local same_view = true
  for _, buf in ipairs(order) do
    if buf ~= dragged and base[buf] == nil then
      same_view = false
      break
    end
  end

  local pos = {}
  for buf, t in pairs(tabs) do
    if buf == dragged then
      pos[buf] = float_left
    elseif same_view then
      pos[buf] = base[buf] or t.target
    else
      pos[buf] = t.target
    end
  end

  return {
    tabs = tabs, order = order, pos = pos, markers = markers,
    dragged = dragged, float = float_left, ncols = layout.ncols,
  }
end

-- Update the drag animation for `win`, the window currently hosting the grabbed
-- tab. Returns true when a slide is in effect, false to redraw instantly.
function M.follow(win, dragged, float_left)
  local a = build(win, dragged, float_left)
  if not a then
    M.clear(win)
    return false
  end
  a.floating = true
  anims[win] = a
  ensure_timer()
  return true
end

-- Ease a window's tabs to their slots with nothing floating: used for the window
-- the grabbed tab just left, so its gap closes with motion instead of snapping.
function M.reflow(win)
  local a = build(win, nil, nil)
  if not a then
    M.clear(win)
    return false
  end
  a.floating = false
  anims[win] = a
  ensure_timer()
  return true
end

-- release the grabbed tab: it stops tracking the cursor and eases into its slot
function M.release(win)
  local a = anims[win]
  if not a then return end
  a.floating = false
  a.float = nil
  ensure_timer()
end

function M.tick()
  local any_moving = false
  for win, a in pairs(anims) do
    if not vim.api.nvim_win_is_valid(win) then
      anims[win] = nil
    else
      local moving = false
      for _, buf in ipairs(a.order) do
        local t = a.tabs[buf]
        if buf == a.dragged and a.floating then
          a.pos[buf] = a.float
        else
          local p = a.pos[buf]
          local d = t.target - p
          if math.abs(d) <= SNAP then
            if p ~= t.target then moving = true end
            a.pos[buf] = t.target
          else
            a.pos[buf] = p + d * EASE
            moving = true
          end
        end
      end
      if not a.floating and not moving then
        local settled = {}
        for buf, t in pairs(a.tabs) do settled[buf] = t.target end
        last_pos[win] = settled
        anims[win] = nil
      elseif moving then
        any_moving = true
      end
    end
  end

  if not any_moving then stop_timer() end
  if any_moving then pcall(vim.cmd, 'redrawstatus!') end
  return any_moving
end

-- the winbar string for `win` this frame, or nil when not animating
function M.frame(win)
  local a = anims[win]
  if not a then return nil end

  local row = {}
  for _, mk in ipairs(a.markers) do
    canvas.paint(row, mk.col, mk.cells, a.ncols)
  end
  for _, buf in ipairs(a.order) do
    canvas.paint(row, a.pos[buf], a.tabs[buf].cells, a.ncols)
  end

  local r = render()
  return canvas.serialize(row, a.ncols, FILL, r.click_prefix, r.close_click_prefix)
end

function M.clear(win)
  if win then
    anims[win] = nil
    last_pos[win] = nil
  else
    anims = {}
    last_pos = {}
  end
  if next(anims) == nil then stop_timer() end
end

return M
