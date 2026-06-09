local M = {}

local config = require('lu5je0.ext.tabline.config')
local state = require('lu5je0.ext.tabline.state')
local naming = require('lu5je0.ext.tabline.naming')

local strwidth = vim.api.nvim_strwidth
local rep = string.rep

local _home = (vim.env.HOME or '') .. '/'

local _cwd_cache = ''
local _modified_cache = {}
local _valid_bufs_cache = {}

local function rel_path(abs)
  local cwd = _cwd_cache
  if abs:sub(1, #cwd) == cwd then
    return abs:sub(#cwd + 1)
  end
  if abs:sub(1, #_home) == _home then
    return '~/' .. abs:sub(#_home + 1)
  end
  return abs
end

local function basename(path)
  return path:match('[^/]+$') or path
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

  if #s == w then
    return s:sub(1, target) .. marker
  end

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

local _click_prefix_cache = {}
local _close_click_prefix_cache = {}

local function click_prefix(buf)
  local c = _click_prefix_cache[buf]
  if c then return c end
  c = '%' .. buf .. "@v:lua.require'lu5je0.ext.tabline.render'._click@"
  _click_prefix_cache[buf] = c
  return c
end

local function close_click_prefix(buf)
  local c = _close_click_prefix_cache[buf]
  if c then return c end
  c = '%' .. buf .. "@v:lua.require'lu5je0.ext.tabline.render'._close_click@"
  _close_click_prefix_cache[buf] = c
  return c
end

local function buffer_segment(buf, ordinal, is_selected, all_basenames, buf_name, is_first, is_focused, target_size)
  local opts = config.options
  target_size = target_size or opts.tab_size
  local devicons = opts.show_devicons and get_devicons() or nil

  local name
  if buf_name == '' then
    local n = state.buffer_name_map[buf]
    name = n and ('Untitled-' .. n) or '[No Name]'
  else
    local base = basename(buf_name)
    if (all_basenames[base] or 0) > 1 then
      name = rel_path(buf_name)
    else
      name = base
    end
  end
  name = truncate(name, opts.max_name_length, opts.truncate_marker)

  local hl_buf = is_selected and 'BufferLineBufferSelected' or 'BufferLineBuffer'

  local prefix
  if state.pick_active and state.pick_map[buf] then
    local hl_pick = is_selected and 'BufferLinePickSelected' or 'BufferLinePick'
    prefix = '%#' .. hl_pick .. '#' .. state.pick_map[buf]
  else
    local hl_num = is_selected and 'BufferLineNumbersSelected' or 'BufferLineNumbers'
    prefix = '%#' .. hl_num .. '#' .. to_superscript(ordinal)
  end

  local icon_part = ''
  local icon_visible_w = 0
  if devicons and buf_name ~= '' then
    local base_for_icon = basename(buf_name)
    local ext = base_for_icon:match('%.([^%.]+)$') or ''
    local icon, icon_hl = devicons.get_icon(base_for_icon, ext, { default = true })
    if icon then
      local combined_hl = get_icon_hl(icon_hl or hl_buf, hl_buf)
      icon_part = '%#' .. combined_hl .. '#' .. icon .. '%#' .. hl_buf .. '# '
      icon_visible_w = 2
    end
  end

  local modified = _modified_cache[buf]

  local prefix_plain = state.pick_active and 1 or (ordinal < 10 and 1 or 2)
  local tail_w = 2
  local overhead = prefix_plain + 1 + icon_visible_w + 1 + tail_w

  local name_w = strwidth(name)
  local content_w = overhead + name_w

  if content_w > target_size then
    local new_max = math.max(1, name_w - (content_w - target_size))
    name = truncate(name, new_max, opts.truncate_marker)
    name_w = strwidth(name)
    content_w = overhead + name_w
  end

  -- build body inline
  local hl_buf_tag = '%#' .. hl_buf .. '#'
  local body = click_prefix(buf) .. prefix .. ' ' .. hl_buf_tag .. icon_part .. name .. ' %X'

  -- build tail inline
  local tail
  if is_selected and is_focused then
    if modified then
      local hl_modified = is_selected and 'BufferLineModifiedSelected' or 'BufferLineModified'
      tail = close_click_prefix(buf) .. '%#' .. hl_modified .. '#' .. opts.modified_icon .. ' %X'
    else
      local hl_close = is_selected and 'BufferLineCloseSelected' or 'BufferLineClose'
      tail = close_click_prefix(buf) .. '%#' .. hl_close .. '#' .. opts.close_icon .. ' %X'
    end
  else
    if modified then
      local hl_modified = is_selected and 'BufferLineModifiedSelected' or 'BufferLineModified'
      tail = '%#' .. hl_modified .. '#' .. opts.modified_icon .. ' '
    else
      tail = hl_buf_tag .. '  '
    end
  end

  -- padding
  local left_pad_str = ''
  local right_pad_str = ''
  if content_w < target_size then
    local total_pad = target_size - content_w
    local left_pad = math.floor(total_pad / 2)
    local right_pad = total_pad - left_pad
    left_pad_str = hl_buf_tag .. rep(' ', left_pad)
    right_pad_str = hl_buf_tag .. rep(' ', right_pad)
  end

  -- separator
  local hl_sep
  if is_selected then
    hl_sep = 'BufferLineIndicatorSelected'
  elseif is_first then
    hl_sep = 'BufferLineSeparatorHidden'
  else
    hl_sep = 'BufferLineSeparator'
  end

  return '%#' .. hl_sep .. '#▎' .. left_pad_str .. hl_buf_tag .. body .. right_pad_str .. tail
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

local function refresh_buf_cache()
  local valid = {}
  local modified = {}
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local buf = info.bufnr
    valid[#valid + 1] = buf
    modified[buf] = info.changed == 1
  end
  _valid_bufs_cache = valid
  _modified_cache = modified
end

function M.build_winbar(win_id)
  _cwd_cache = vim.fn.getcwd() .. '/'
  refresh_buf_cache()
  local all_valid = _valid_bufs_cache
  if #all_valid == 0 then return '%#BufferLineFill#' end

  local bufs
  local single_win = true
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= win_id then
      local cfg = vim.api.nvim_win_get_config(win)
      if not cfg.relative or cfg.relative == '' then
        local bt = vim.api.nvim_get_option_value('buftype', { buf = vim.api.nvim_win_get_buf(win) })
        if bt == '' then
          single_win = false
          break
        end
      end
    end
  end

  if single_win then
    bufs = all_valid
    state.win_bufs[win_id] = bufs
  else
    local win_bufs = state.win_bufs[win_id]
    if not win_bufs or #win_bufs == 0 then
      local buf = vim.api.nvim_win_get_buf(win_id)
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_get_option_value('buflisted', { buf = buf }) then
        win_bufs = { buf }
        state.win_bufs[win_id] = win_bufs
      else
        return '%#BufferLineFill#'
      end
    end

    local valid_set = {}
    for _, b in ipairs(all_valid) do valid_set[b] = true end

    bufs = {}
    for _, b in ipairs(win_bufs) do
      if valid_set[b] then bufs[#bufs + 1] = b end
    end
    state.win_bufs[win_id] = bufs
    if #bufs == 0 then return '%#BufferLineFill#' end
  end

  naming.assign(all_valid)

  local buf_names = {}
  local all_basenames = {}
  for _, b in ipairs(bufs) do
    local n = vim.api.nvim_buf_get_name(b)
    buf_names[b] = n
    if n ~= '' then
      local base = basename(n)
      all_basenames[base] = (all_basenames[base] or 0) + 1
    end
  end

  local current = vim.api.nvim_win_get_buf(win_id)
  local is_focused = (win_id == state.focused_win)
  local current_idx = 1
  for i, b in ipairs(bufs) do
    if b == current then current_idx = i; break end
  end

  local seg_width = config.options.tab_size + 1
  local segments = {}
  for i, buf in ipairs(bufs) do
    local is_selected = (buf == current)
    segments[i] = buffer_segment(buf, i, is_selected, all_basenames, buf_names[buf], i == 1, is_focused)
  end

  local available = vim.api.nvim_win_get_width(win_id)

  local left_start, right_end = 1, #bufs
  local left_hidden, right_hidden = 0, 0

  local function marker_width(count)
    if count <= 0 then return 0 end
    local digits = count < 10 and 1 or (count < 100 and 2 or 3)
    return digits + 4
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
    else
      break
    end
  end

  local used_extra = 0
  local left_partial, right_partial

  local function leftover()
    return available - total_width() - used_extra
  end

  local function min_partial_for(ordinal)
    local prefix_w = ordinal < 10 and 1 or (ordinal < 100 and 2 or 3)
    return 1 + prefix_w + 1 + 2 + 1 + 1 + 2  -- sep + prefix + sp + icon + sp + name(1) + tail
  end

  if right_hidden > 0 then
    local idx = right_end + 1
    local buf = bufs[idx]
    local new_hidden = right_hidden - 1
    local gained = marker_width(right_hidden) - marker_width(new_hidden)
    local partial_size = leftover() + gained
    if partial_size >= min_partial_for(idx) then
      right_partial = buffer_segment(buf, idx, false, all_basenames, buf_names[buf], false, is_focused, partial_size - 1)
      right_hidden = new_hidden
      used_extra = used_extra + partial_size
    end
  end

  if left_hidden > 0 then
    local idx = left_start - 1
    local buf = bufs[idx]
    local new_hidden = left_hidden - 1
    local gained = marker_width(left_hidden) - marker_width(new_hidden)
    local partial_size = leftover() + gained
    if partial_size >= min_partial_for(idx) then
      left_partial = buffer_segment(buf, idx, false, all_basenames, buf_names[buf], idx == 1, is_focused, partial_size - 1)
      left_hidden = new_hidden
      used_extra = used_extra + partial_size
    end
  end

  local parts = {}
  local left_marker = make_trunc_marker(LEFT_TRUNC, left_hidden)
  if left_marker ~= '' then parts[#parts + 1] = left_marker end
  if left_partial then parts[#parts + 1] = left_partial end

  for i = left_start, right_end do
    parts[#parts + 1] = segments[i]
  end

  if right_partial then parts[#parts + 1] = right_partial end
  local right_marker = make_trunc_marker(RIGHT_TRUNC, right_hidden)
  if right_marker ~= '' then parts[#parts + 1] = right_marker end

  parts[#parts + 1] = '%#BufferLineFill#'
  return table.concat(parts)
end

function M.winbar(win_id)
  local ok, str = pcall(M.build_winbar, win_id)
  if not ok then return '' end
  return str
end

M.clear_icon_hl_cache = clear_icon_hl_cache

local function close_buf_in_win(bufnr)
  local win = vim.api.nvim_get_current_win()
  local win_bufs = state.win_bufs[win]
  if win_bufs and vim.api.nvim_win_get_buf(win) == bufnr then
    -- build valid list and find target
    local filtered = {}
    local cur_idx
    for _, b in ipairs(win_bufs) do
      if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
        filtered[#filtered + 1] = b
        if b == bufnr then cur_idx = #filtered end
      end
    end
    if cur_idx and #filtered > 1 then
      local target
      if cur_idx < #filtered then
        target = filtered[cur_idx + 1]
      else
        target = filtered[cur_idx - 1]
      end
      vim.api.nvim_set_current_buf(target)
    end
  end

  -- remove from list
  if win_bufs then
    local new_list = {}
    for _, b in ipairs(win_bufs) do
      if b ~= bufnr then new_list[#new_list + 1] = b end
    end
    state.win_bufs[win] = new_list
  end

  -- only bdelete if no window owns this buffer
  for _, bufs in pairs(state.win_bufs) do
    for _, b in ipairs(bufs) do
      if b == bufnr then return end
    end
  end
  vim.cmd('silent! bdelete ' .. bufnr)
end

function M._click(bufnr, _clicks, button, _mods)
  if button == 'l' then
    pcall(vim.api.nvim_set_current_buf, bufnr)
  elseif button == 'm' then
    pcall(close_buf_in_win, bufnr)
  end
end

function M._close_click(bufnr, _clicks, _button, _mods)
  pcall(close_buf_in_win, bufnr)
end

return M
