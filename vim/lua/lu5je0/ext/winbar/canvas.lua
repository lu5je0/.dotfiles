-- Cell canvas for the winbar slide animation. Parses the winbar-markup produced
-- by render.buffer_segment into per-column cells, lets those cells be painted at
-- arbitrary (possibly overlapping / off-screen) columns, and serializes the
-- result back into a winbar string with click regions re-derived.
--
-- Only used while a slide animation is running; the static render path stays on
-- plain string concatenation.
local M = {}

local strwidth = vim.api.nvim_strwidth

local function char_len(byte)
  if byte < 0x80 then return 1 end
  if byte < 0xE0 then return 2 end
  if byte < 0xF0 then return 3 end
  return 4
end

-- Parse a winbar-markup segment into a flat list of cells:
--   { ch = <str>, hl = <group>, buf = <n|nil>, click = 'tab'|'close'|nil, w = 1|2 }
-- A width-2 cell is followed by a { cont = true } placeholder so column math is
-- exact.
function M.parse(markup)
  local cells = {}
  local hl = 'Normal'
  local click_buf, click_kind
  local i, len = 1, #markup
  while i <= len do
    if markup:sub(i, i) == '%' then
      local c2 = markup:sub(i + 1, i + 1)
      if c2 == '#' then
        local close = markup:find('#', i + 2, true)
        hl = markup:sub(i + 2, close - 1)
        i = close + 1
      elseif c2 == 'X' then
        click_buf, click_kind = nil, nil
        i = i + 2
      elseif c2 == '%' then
        cells[#cells + 1] = { ch = '%', hl = hl, buf = click_buf, click = click_kind, w = 1 }
        i = i + 2
      elseif c2:match('%d') or c2 == '@' then
        -- %<digits>@funcref@ : a click region open
        local digits, rest = markup:match('^%%(%d*)@()', i)
        local func_end = markup:find('@', rest, true)
        local func = markup:sub(rest, func_end - 1)
        click_buf = tonumber(digits)
        click_kind = func:find('_close_click', 1, true) and 'close' or 'tab'
        i = func_end + 1
      else
        i = i + 1 -- unknown %-item, skip the '%'
      end
    else
      local clen = char_len(markup:byte(i))
      local ch = markup:sub(i, i + clen - 1)
      local w = clen == 1 and 1 or strwidth(ch)
      if w < 1 then w = 1 end
      cells[#cells + 1] = { ch = ch, hl = hl, buf = click_buf, click = click_kind, w = w }
      if w == 2 then
        cells[#cells + 1] = { cont = true }
      end
      i = i + clen
    end
  end
  return cells
end

-- Paint a parsed cell list onto `row` starting at (rounded) column `start_col`.
-- Cells outside [1, ncols] are clipped. Later paints overwrite earlier ones, so
-- pass the tab that should stay on top last.
function M.paint(row, start_col, cells, ncols)
  local col = math.floor(start_col + 0.5)
  for _, cell in ipairs(cells) do
    if cell.cont then
      -- handled together with its lead cell below
    elseif cell.w == 2 then
      local fits = col >= 1 and (col + 1) <= ncols
      if fits then
        row[col] = { ch = cell.ch, hl = cell.hl, buf = cell.buf, click = cell.click, wide = true }
        row[col + 1] = { cont = true, hl = cell.hl, buf = cell.buf, click = cell.click, lead = col }
      else
        for k = 0, 1 do
          local c = col + k
          if c >= 1 and c <= ncols then
            row[c] = { ch = ' ', hl = cell.hl, buf = cell.buf, click = cell.click }
          end
        end
      end
      col = col + 2
    else
      if col >= 1 and col <= ncols then
        row[col] = { ch = cell.ch, hl = cell.hl, buf = cell.buf, click = cell.click }
      end
      col = col + 1
    end
  end
end

-- Fix wide-char pairs broken by an overlapping paint: a lead whose continuation
-- was overwritten (or vice-versa) degrades to a blank so the row keeps its exact
-- column count.
local function normalize(row, last)
  for c = 1, last do
    local cell = row[c]
    if cell then
      if cell.wide then
        local nxt = row[c + 1]
        if not (nxt and nxt.cont and nxt.lead == c) then
          row[c] = { ch = ' ', hl = cell.hl, buf = cell.buf, click = cell.click }
        end
      elseif cell.cont then
        local prev = row[cell.lead]
        if not (prev and prev.wide and cell.lead == c - 1) then
          row[c] = { ch = ' ', hl = cell.hl, buf = cell.buf, click = cell.click }
        end
      end
    end
  end
end

-- Serialize the painted row into a winbar string, coalescing highlight groups
-- and re-emitting click regions per run of same-owner cells.
function M.serialize(row, ncols, fill_hl, click_prefix, close_click_prefix)
  local last = 0
  for c = ncols, 1, -1 do
    if row[c] then last = c; break end
  end
  if last == 0 then return '%#' .. fill_hl .. '#' end

  normalize(row, last)

  local parts = {}
  local cur_hl, cur_click
  for c = 1, last do
    local cell = row[c] or { ch = ' ', hl = fill_hl }
    if not cell.cont then
      local key = cell.click and (cell.click .. tostring(cell.buf)) or nil
      if key ~= cur_click then
        if cur_click then parts[#parts + 1] = '%X' end
        if key then
          parts[#parts + 1] = cell.click == 'close'
            and close_click_prefix(cell.buf)
            or click_prefix(cell.buf)
        end
        cur_click = key
      end
      if cell.hl ~= cur_hl then
        parts[#parts + 1] = '%#' .. cell.hl .. '#'
        cur_hl = cell.hl
      end
      parts[#parts + 1] = cell.ch
    end
  end
  if cur_click then parts[#parts + 1] = '%X' end
  parts[#parts + 1] = '%#' .. fill_hl .. '#'
  return table.concat(parts)
end

return M
