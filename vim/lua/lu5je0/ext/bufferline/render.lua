local M = {}

local config = require('lu5je0.ext.bufferline.config')
local state = require('lu5je0.ext.bufferline.state')
local naming = require('lu5je0.ext.bufferline.naming')
local offsets = require('lu5je0.ext.bufferline.offsets')

local superscripts = { '⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹' }

local function to_superscript(n)
  local s = tostring(n)
  local result = {}
  for i = 1, #s do
    local digit = tonumber(s:sub(i, i))
    result[#result + 1] = superscripts[digit + 1]
  end
  return table.concat(result)
end

local icon_hl_cache = {}

local function get_icon_hl(base_icon_hl, tab_bg_hl)
  local key = base_icon_hl .. ':' .. tab_bg_hl
  if icon_hl_cache[key] then return icon_hl_cache[key] end

  local icon_def = vim.api.nvim_get_hl(0, { name = base_icon_hl, link = false })
  local tab_def = vim.api.nvim_get_hl(0, { name = tab_bg_hl, link = false })

  local group_name = 'BufferLineIcon_' .. base_icon_hl .. '_' .. tab_bg_hl
  vim.api.nvim_set_hl(0, group_name, {
    fg = icon_def.fg,
    bg = tab_def.bg,
  })
  icon_hl_cache[key] = group_name
  return group_name
end

local function clear_icon_hl_cache()
  icon_hl_cache = {}
end

local function get_devicons()
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if ok then return devicons end
  return nil
end

local function display_name(buf, all_basenames, modified_count)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then
    local n = state.buffer_name_map[buf]
    return n and ('Untitled-' .. n) or '[No Name]'
  end
  local base = vim.fs.basename(name)
  if (all_basenames[base] or 0) > 1 then
    local rel = vim.fn.fnamemodify(name, ':~:.')
    return rel
  end
  return base
end

local function truncate(s, max, marker)
  local w = vim.fn.strdisplaywidth(s)
  if w <= max then return s end
  local mw = vim.fn.strdisplaywidth(marker)
  return vim.fn.strcharpart(s, 0, math.max(max - mw, 1)) .. marker
end

local function pad_to(s, target)
  local w = vim.fn.strdisplaywidth(s)
  if w >= target then return s end
  return s .. string.rep(' ', target - w)
end

local function buffer_segment(buf, ordinal, is_selected, all_basenames)
  local opts = config.options
  local devicons = config.options.show_devicons and get_devicons() or nil

  local name = display_name(buf, all_basenames)
  name = truncate(name, opts.max_name_length, opts.truncate_marker)

  local hl_buf = is_selected and 'BufferLineBufferSelected' or 'BufferLineBuffer'
  local hl_num = is_selected and 'BufferLineNumbersSelected' or 'BufferLineNumbers'
  local hl_close = is_selected and 'BufferLineCloseSelected' or 'BufferLineClose'
  local hl_modified = is_selected and 'BufferLineModifiedSelected' or 'BufferLineModified'

  local prefix
  if state.pick_active then
    local letter = state.pick_map[buf] or '?'
    local hl_pick = is_selected and 'BufferLinePickSelected' or 'BufferLinePick'
    prefix = string.format('%%#%s#%s', hl_pick, letter)
  else
    prefix = string.format('%%#%s#%s', hl_num, to_superscript(ordinal))
  end

  local icon_part = ''
  if devicons then
    local fname = vim.api.nvim_buf_get_name(buf)
    local ext = vim.fn.fnamemodify(fname, ':e')
    local icon, icon_hl = devicons.get_icon(vim.fs.basename(fname), ext, { default = true })
    if icon then
      local combined_hl = get_icon_hl(icon_hl or hl_buf, hl_buf)
      icon_part = string.format('%%#%s#%s%%#%s# ', combined_hl, icon, hl_buf)
    end
  end

  local modified = vim.bo[buf].modified
  local tail
  if modified then
    tail = string.format('%%#%s#%s', hl_modified, opts.modified_icon)
  else
    tail = string.format('%%#%s#%s', hl_close, opts.close_icon)
  end

  local body = string.format(' %s %%#%s#%s%s ', prefix, hl_buf, icon_part, name)

  body = string.format('%%%d@v:lua.require\'lu5je0.ext.bufferline.render\'._click@%s%%X', buf, body)
  tail = string.format('%%%d@v:lua.require\'lu5je0.ext.bufferline.render\'._close_click@%s %%X', buf, tail)

  local inner = string.format('%%#%s#%s%s', hl_buf, body, tail)
  local fixed = string.format('%%-%d.%d(%s%%)', opts.tab_size, opts.tab_size, inner)

  local hl_sep = is_selected and 'BufferLineIndicatorSelected' or 'BufferLineSeparator'
  local sep = string.format('%%#%s#▎', hl_sep)

  local segment = string.format('%s%s', sep, fixed)
  return segment
end

local function measure_segment_width(segment)
  local plain = segment:gsub('%%#[^#]*#', ''):gsub('%%[0-9]*@[^@]*@', ''):gsub('%%X', ''):gsub('%%T', '')
  return vim.fn.strdisplaywidth(plain)
end

local LEFT_TRUNC = ''
local RIGHT_TRUNC = ''

local function make_trunc_marker(icon, count)
  if count <= 0 then return '', 0 end
  local text = string.format(' %d %s ', count, icon)
  local s = string.format('%%#BufferLineTruncMarker#%s', text)
  return s, vim.fn.strdisplaywidth(text)
end

function M.build()
  local bufs = require('lu5je0.core.buffers').valid_buffers()
  naming.assign(bufs)

  local all_basenames = {}
  for _, b in ipairs(bufs) do
    local n = vim.api.nvim_buf_get_name(b)
    if n ~= '' then
      local base = vim.fs.basename(n)
      all_basenames[base] = (all_basenames[base] or 0) + 1
    end
  end

  state.ordinal_to_buf = {}
  for i, b in ipairs(bufs) do state.ordinal_to_buf[i] = b end

  local current = vim.api.nvim_get_current_buf()
  local current_idx = 1
  for i, b in ipairs(bufs) do
    if b == current then current_idx = i; break end
  end

  local segments = {}
  local widths = {}
  local seg_width = config.options.tab_size + 1
  for i, buf in ipairs(bufs) do
    local is_selected = (buf == current)
    local seg = buffer_segment(buf, i, is_selected, all_basenames)
    segments[i] = seg
    widths[i] = seg_width
  end

  local offset_str = offsets.compute()
  local offset_w = measure_segment_width(offset_str)

  local tabpages = vim.api.nvim_list_tabpages()
  local tab_section_w = 0
  if #tabpages > 1 then
    tab_section_w = #tabpages * 4
  end

  local available = vim.o.columns - offset_w - tab_section_w

  local left_start, right_end = 1, #bufs
  local left_hidden, right_hidden = 0, 0

  local function total_width()
    local w = 0
    for i = left_start, right_end do
      w = w + widths[i]
    end
    local lm_w = left_hidden > 0 and (vim.fn.strdisplaywidth(string.format(' %d %s ', left_hidden, LEFT_TRUNC))) or 0
    local rm_w = right_hidden > 0 and (vim.fn.strdisplaywidth(string.format(' %d %s ', right_hidden, RIGHT_TRUNC))) or 0
    return w + lm_w + rm_w
  end

  while total_width() > available and (left_start < current_idx or right_end > current_idx) do
    local before_len = current_idx - left_start
    local after_len = right_end - current_idx
    if before_len >= after_len and left_start < current_idx then
      left_start = left_start + 1
      left_hidden = left_hidden + 1
    elseif right_end > current_idx then
      right_end = right_end - 1
      right_hidden = right_hidden + 1
    elseif left_start < current_idx then
      left_start = left_start + 1
      left_hidden = left_hidden + 1
    else
      break
    end
  end

  local parts = { offset_str }
  local left_marker, _ = make_trunc_marker(LEFT_TRUNC, left_hidden)
  if left_marker ~= '' then parts[#parts + 1] = left_marker end

  for i = left_start, right_end do
    parts[#parts + 1] = segments[i]
  end

  local right_marker, _ = make_trunc_marker(RIGHT_TRUNC, right_hidden)
  if right_marker ~= '' then parts[#parts + 1] = right_marker end

  local tab_section = ''
  if #tabpages > 1 then
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local tab_parts = {}
    for i, tp in ipairs(tabpages) do
      local is_cur = (tp == cur_tab)
      local sep_hl = is_cur and 'BufferLineTabSeparatorSelected' or 'BufferLineTabSeparator'
      local tab_hl = is_cur and 'BufferLineTabSelected' or 'BufferLineTab'
      tab_parts[#tab_parts + 1] = string.format('%%#%s#▎%%#%s#%%%dT %d ', sep_hl, tab_hl, i, i)
    end
    tab_section = table.concat(tab_parts)
  end

  parts[#parts + 1] = '%#BufferLineFill#'
  if tab_section ~= '' then
    parts[#parts + 1] = '%='
    parts[#parts + 1] = tab_section
  end
  return table.concat(parts)
end

function M.tabline()
  local ok, str = pcall(M.build)
  if not ok then return '' end
  return str
end

M.clear_icon_hl_cache = clear_icon_hl_cache

function M._click(bufnr, _clicks, button, _mods)
  if button == 'l' then
    pcall(vim.api.nvim_set_current_buf, bufnr)
  elseif button == 'm' then
    pcall(vim.cmd, 'bdelete ' .. bufnr)
  end
end

function M._close_click(bufnr, _clicks, _button, _mods)
  pcall(vim.cmd, 'bdelete ' .. bufnr)
end

return M
