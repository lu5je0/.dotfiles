local M = {}

local BORDER_SIZE = {
  none = { 0, 0 },
  single = { 2, 2 },
  double = { 2, 2 },
  rounded = { 2, 2 },
  solid = { 2, 2 },
  shadow = { 1, 1 },
}

local function border_error(border)
  error(string.format('invalid floating preview border: %s', vim.inspect(border)))
end

-- Mirrors Neovim upstream border size logic, including tuple/list border forms.
local function get_border_size(opts)
  local border = opts and opts.border or vim.o.winborder
  if border == '' then
    border = 'none'
  end

  if type(border) == 'string' then
    if not BORDER_SIZE[border] then
      border_error(border)
    end
    local r = BORDER_SIZE[border]
    return r[1], r[2]
  end

  if type(border) ~= 'table' then
    border_error(border)
  end

  if 8 % #border ~= 0 then
    border_error(border)
  end

  local top = border[2]
  local right = border[4]
  local bottom = border[6]
  local left = border[8]

  local function normalize_entry(e)
    if e == nil then
      return ''
    end
    if type(e) == 'table' then
      return e[1] or ''
    end
    if type(e) == 'string' then
      return e
    end
    border_error(border)
  end

  top = normalize_entry(top)
  right = normalize_entry(right)
  bottom = normalize_entry(bottom)
  left = normalize_entry(left)

  local function border_height(e)
    return (e == '' and 0) or 1
  end

  local height = border_height(top) + border_height(bottom)
  local width = vim.fn.strdisplaywidth(right) + vim.fn.strdisplaywidth(left)
  return height, width
end

local function max_window_height()
  local max_height = vim.g.translator_window_max_height or 999
  if type(max_height) == 'number' and max_height > 0 and max_height < 1 then
    max_height = math.floor(max_height * vim.o.lines)
  end
  if type(max_height) ~= 'number' or max_height <= 0 then
    max_height = 999
  end
  return math.floor(max_height)
end

function M.calc_size(lines)
  local width = math.max(1, math.min(40, vim.o.columns - 4))
  local height = math.max(1, math.min(#lines, max_window_height()))
  return width, height
end

-- Mirrors Neovim's make_floating_popup_options behavior for cursor-relative popups.
function M.make_config(width, height, opts)
  opts = opts or {}
  local anchor = ''

  local lines_above = vim.fn.winline() - 1
  local lines_below = vim.fn.winheight(0) - lines_above

  local anchor_bias = opts.anchor_bias or 'auto'
  local anchor_below
  if anchor_bias == 'below' then
    anchor_below = (lines_below > lines_above) or (height <= lines_below)
  elseif anchor_bias == 'above' then
    local anchor_above = (lines_above > lines_below) or (height <= lines_above)
    anchor_below = not anchor_above
  else
    anchor_below = lines_below > lines_above
  end

  local border_height = get_border_size(opts)
  local row
  if anchor_below then
    anchor = anchor .. 'N'
    height = math.max(math.min(lines_below - border_height, height), 0)
    row = 1
  else
    anchor = anchor .. 'S'
    height = math.max(math.min(lines_above - border_height, height), 0)
    row = 0
  end

  local wincol = vim.fn.wincol()
  local col
  if wincol + width + (opts.offset_x or 0) <= vim.o.columns then
    anchor = anchor .. 'W'
    col = 0
  else
    anchor = anchor .. 'E'
    col = 1
  end

  local title = ((opts.border or vim.o.winborder ~= '') and opts.title) and opts.title or nil
  local title_pos = title and (opts.title_pos or 'center') or nil

  local final_col = col + (opts.offset_x or 0)
  if anchor:sub(2, 2) == 'W' then
    final_col = final_col - 4
  end

  return {
    anchor = anchor,
    row = row + (opts.offset_y or 0),
    col = final_col,
    height = math.max(1, height),
    width = math.max(1, width),
    focusable = opts.focusable ~= false,
    relative = 'cursor',
    style = 'minimal',
    border = opts.border,
    zindex = opts.zindex or 60,
    title = title,
    title_pos = title_pos,
  }
end

return M
