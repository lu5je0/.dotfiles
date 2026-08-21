-- Slide animation for winbar tab dragging. While dragging, the grabbed tab
-- follows the cursor (its column tracks the mouse, no easing) and the other
-- tabs ease aside to open a gap; on release the grabbed tab eases into that gap.
-- Reordering is driven by the grabbed tab's centre crossing a slot boundary
-- (>50% overlap), computed by the drag layer.
--
-- Scope: pure within-window drags where every tab fits (no truncation).
-- Cross-window moves / truncated strips fall back to an instant redraw.
--
-- `state.tab_regions` is kept at the settled slot layout so hit-testing in
-- *other* windows stays stable while these visuals slide.
local M = {}

local state = require('lu5je0.ext.winbar.state')
local canvas = require('lu5je0.ext.winbar.canvas')

local FILL = 'BufferLineFill'
local STEP_MS = 16
local EASE = 0.34   -- exponential ease-out factor per tick (non-grabbed tabs)
local SNAP = 0.5    -- within this many columns of target -> considered arrived

-- win -> {
--   cells    = { [buf] = parsed cell list },
--   order    = { buf, ... },              -- paint order (grabbed drawn last)
--   target   = { [buf] = column },        -- settled slot column
--   pos      = { [buf] = column (float) },-- current drawn column
--   dragged  = buf,
--   float    = column,                    -- where the grabbed tab is drawn
--   floating = bool,                      -- true until release
--   W, ncols,
-- }
local anims = {}
-- win -> { [buf] = column } : last settled positions, seed for the next drag
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

-- record the current static slot layout as the seed positions for a drag.
function M.seed(win)
  local segs, seg_width, ncols = render().ordered_segments(win)
  if #segs * seg_width > ncols then
    last_pos[win] = nil
    return
  end
  local pos = {}
  for i, seg in ipairs(segs) do
    pos[seg.buf] = (i - 1) * seg_width + 1
  end
  last_pos[win] = pos
end

-- Update the drag animation for the current order (grabbed tab already placed
-- at its target index by the caller) and floating column. Returns true when a
-- slide is in effect, false when the caller should just redraw instantly.
function M.follow(win, dragged, float_left)
  if not vim.api.nvim_win_is_valid(win) then return false end
  local segs, W, ncols = render().ordered_segments(win)
  if #segs == 0 or #segs * W > ncols then
    M.clear(win)
    return false
  end

  local target, cells, order, regions = {}, {}, {}, {}
  for i, seg in ipairs(segs) do
    local buf = seg.buf
    target[buf] = (i - 1) * W + 1
    cells[buf] = canvas.parse(seg.markup)
    order[i] = buf
    regions[i] = { buf = buf, ordinal = i, from = target[buf], to = target[buf] + W - 1 }
  end
  state.tab_regions[win] = regions

  local prev = anims[win]
  local base = (prev and prev.pos) or last_pos[win] or target
  local pos = {}
  for _, buf in ipairs(order) do
    pos[buf] = (buf == dragged) and float_left or (base[buf] or target[buf])
  end

  anims[win] = {
    cells = cells, order = order, target = target, pos = pos,
    dragged = dragged, float = float_left, floating = true, W = W, ncols = ncols,
  }
  ensure_timer()
  return true
end

-- release the grabbed tab: it stops following the cursor and eases into its slot.
function M.release(win)
  local a = anims[win]
  if not a then return end
  a.floating = false
  a.float = nil
  ensure_timer()
end

-- Advance every active animation one tick.
function M.tick()
  local any_moving = false
  for win, a in pairs(anims) do
    if not vim.api.nvim_win_is_valid(win) then
      anims[win] = nil
    else
      local moving = false
      for _, buf in ipairs(a.order) do
        if buf == a.dragged and a.floating then
          a.pos[buf] = a.float
        else
          local p, t = a.pos[buf], a.target[buf]
          local d = t - p
          if math.abs(d) <= SNAP then
            if p ~= t then moving = true end
            a.pos[buf] = t
          else
            a.pos[buf] = p + d * EASE
            moving = true
          end
        end
      end
      if not a.floating and not moving then
        last_pos[win] = a.target
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

-- The winbar string for `win` this frame, or nil when not animating.
function M.frame(win)
  local a = anims[win]
  if not a then return nil end

  local row = {}
  for _, buf in ipairs(a.order) do
    if buf ~= a.dragged then
      canvas.paint(row, a.pos[buf], a.cells[buf], a.ncols)
    end
  end
  -- grabbed tab painted last so it stays on top of its neighbours
  local dcol = a.floating and a.float or a.pos[a.dragged]
  if a.cells[a.dragged] then
    canvas.paint(row, dcol, a.cells[a.dragged], a.ncols)
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
