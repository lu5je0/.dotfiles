local M = {}

local config = require('lu5je0.ext.tabline.config')
local state = require('lu5je0.ext.tabline.state')
local naming = require('lu5je0.ext.tabline.naming')
local offsets = require('lu5je0.ext.tabline.offsets')

local strwidth = vim.api.nvim_strwidth

local _home = (vim.env.HOME or '') .. '/'

local function rel_path(abs)
  local cwd = vim.fn.getcwd() .. '/'
  if abs:sub(1, #cwd) == cwd then
    return abs:sub(#cwd + 1)
  end
  if abs:sub(1, #_home) == _home then
    return '~/' .. abs:sub(#_home + 1)
  end
  return abs
end

local superscripts = { '⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹' }
local superscript_cache = {}
for i = 0, 99 do
  local s = tostring(i)
  local result = {}
  for j = 1, #s do
    result[j] = superscripts[tonumber(s:sub(j, j)) + 1]
  end
  superscript_cache[i] = table.concat(result)
end

local function to_superscript(n)
  return superscript_cache[n] or superscript_cache[0]
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

local _devicons_cache
local _devicons_loaded = false

local function get_devicons()
  if _devicons_loaded then return _devicons_cache end
  _devicons_loaded = true
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  _devicons_cache = ok and devicons or nil
  return _devicons_cache
end

local function truncate(s, max, marker)
  local w = strwidth(s)
  if w <= max then return s end
  local mw = strwidth(marker)
  local target = max - mw
  if target <= 0 then return marker end

  -- fast path: pure ASCII
  if #s == w then
    return s:sub(1, target) .. marker
  end

  -- slow path: multi-byte
  local acc_w = 0
  local byte_end = 0
  local len = #s
  local i = 1
  while i <= len do
    local b = s:byte(i)
    local char_len
    if b < 0x80 then char_len = 1
    elseif b < 0xE0 then char_len = 2
    elseif b < 0xF0 then char_len = 3
    else char_len = 4
    end
    local ch_w = (char_len == 1) and 1 or strwidth(s:sub(i, i + char_len - 1))
    if acc_w + ch_w > target then break end
    acc_w = acc_w + ch_w
    byte_end = i + char_len - 1
    i = i + char_len
  end
  return s:sub(1, byte_end) .. marker
end

local function pad_to(s, target)
  local w = strwidth(s)
  if w >= target then return s end
  return s .. string.rep(' ', target - w)
end

local function buffer_segment(buf, ordinal, is_selected, all_basenames, buf_name)
  local opts = config.options
  local devicons = config.options.show_devicons and get_devicons() or nil

  local name
  if buf_name == '' then
    local n = state.buffer_name_map[buf]
    name = n and ('Untitled-' .. n) or '[No Name]'
  else
    local base = vim.fs.basename(buf_name)
    if (all_basenames[base] or 0) > 1 then
      name = rel_path(buf_name)
    else
      name = base
    end
  end
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
  if devicons and buf_name ~= '' then
    local base_for_icon = vim.fs.basename(buf_name)
    local ext = base_for_icon:match('%.([^%.]+)$') or ''
    local icon, icon_hl = devicons.get_icon(base_for_icon, ext, { default = true })
    if icon then
      local combined_hl = get_icon_hl(icon_hl or hl_buf, hl_buf)
      icon_part = string.format('%%#%s#%s%%#%s# ', combined_hl, icon, hl_buf)
    end
  end

  local modified = vim.bo[buf].modified

  local function build_body_tail(disp_name)
    local b = string.format('%s %%#%s#%s%s ', prefix, hl_buf, icon_part, disp_name)
    b = string.format('%%%d@v:lua.require\'lu5je0.ext.tabline.render\'._click@%s%%X', buf, b)
    local t
    if is_selected then
      if modified then
        t = string.format('%%#%s#%s', hl_modified, opts.modified_icon)
      else
        t = string.format('%%#%s#%s', hl_close, opts.close_icon)
      end
      t = string.format('%%%d@v:lua.require\'lu5je0.ext.tabline.render\'._close_click@%s %%X', buf, t)
    else
      if modified then
        t = string.format('%%#%s#%s ', hl_modified, opts.modified_icon)
      else
        t = string.format('%%#%s#  ', hl_buf)
      end
    end
    return b, t
  end

  -- Pre-compute the visible width of parts excluding name
  -- Structure: prefix_text + ' ' + icon_visible + name + ' ' + tail_visible
  local prefix_plain = state.pick_active and 1 or (ordinal < 10 and 1 or 2)
  local icon_visible_w = 0
  if icon_part ~= '' then
    icon_visible_w = 2  -- icon char (1) + space (1)
  end
  -- tail: selected = icon(1) + space(1) = 2; non-selected = 2 (spaces or modified+space)
  local tail_w = 2
  local overhead = prefix_plain + 1 + icon_visible_w + 1 + tail_w  -- prefix + sp + icon + name_placeholder + sp + tail

  local name_w = strwidth(name)
  local content_w = overhead + name_w

  if content_w > opts.tab_size then
    local new_max = math.max(1, name_w - (content_w - opts.tab_size))
    name = truncate(name, new_max, opts.truncate_marker)
    name_w = strwidth(name)
    content_w = overhead + name_w
  end

  local body, tail = build_body_tail(name)

  local left_pad_str = ''
  local right_pad_str = ''
  if content_w < opts.tab_size then
    local total_pad = opts.tab_size - content_w
    local left_pad = math.floor(total_pad / 2)
    local right_pad = total_pad - left_pad
    left_pad_str = string.format('%%#%s#%s', hl_buf, string.rep(' ', left_pad))
    right_pad_str = string.format('%%#%s#%s', hl_buf, string.rep(' ', right_pad))
  end

  local hl_sep = is_selected and 'BufferLineIndicatorSelected' or 'BufferLineSeparator'
  local sep = string.format('%%#%s#▎', hl_sep)

  local segment = string.format('%s%s%%#%s#%s%s%s', sep, left_pad_str, hl_buf, body, right_pad_str, tail)
  return segment
end

local function measure_segment_width(segment)
  local plain = segment:gsub('%%#[^#]*#', ''):gsub('%%[0-9]*@[^@]*@', ''):gsub('%%X', ''):gsub('%%T', '')
  return strwidth(plain)
end

local LEFT_TRUNC = ''
local RIGHT_TRUNC = ''

local function make_trunc_marker(icon, count)
  if count <= 0 then return '', 0 end
  local text = string.format(' %d %s ', count, icon)
  local s = string.format('%%#BufferLineTruncMarker#%s', text)
  return s, strwidth(text)
end

function M.build()
  local bufs = require('lu5je0.core.buffers').valid_buffers()
  naming.assign(bufs)

  local buf_names = {}
  local all_basenames = {}
  for _, b in ipairs(bufs) do
    local n = vim.api.nvim_buf_get_name(b)
    buf_names[b] = n
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
    local seg = buffer_segment(buf, i, is_selected, all_basenames, buf_names[buf])
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

  local function marker_width(count)
    if count <= 0 then return 0 end
    local digits = count < 10 and 1 or (count < 100 and 2 or 3)
    return digits + 4  -- space + digits + space + icon(1) + space
  end

  local function total_width()
    local w = (right_end - left_start + 1) * seg_width
    return w + marker_width(left_hidden) + marker_width(right_hidden)
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
