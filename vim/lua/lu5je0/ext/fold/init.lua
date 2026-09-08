local api = vim.api
local fn = vim.fn

local M = {}

local BASE_HIGHLIGHT = 'FoldTextNormal'
local TREESITTER_PRIORITY = vim.hl.priorities.treesitter

local fold_suffix_filetypes = {
  c = true,
  cpp = true,
  html = true,
  java = true,
  json = true,
  lua = true,
  nix = true,
  python = true,
  rust = true,
  xml = true,
}

local buffer_cache = {}
local capture_highlight_cache = {}
local query_cache = {}
local syntax_highlight_cache = {}
local attached_buffers = {}

local function should_append_end_line(bufnr)
  return fold_suffix_filetypes[vim.bo[bufnr].filetype] == true
end

local function has_highlight_attributes(name)
  local ok, attrs = pcall(api.nvim_get_hl, 0, { name = name, link = false })
  return ok and next(attrs) ~= nil
end

local function resolve_capture_highlight(capture, lang)
  if capture:sub(1, 1) == '_' then
    return nil
  end

  local key = lang .. '\0' .. capture
  local cached = capture_highlight_cache[key]
  if cached ~= nil then
    return cached or nil
  end

  local highlight = '@' .. capture
  local lang_highlight = highlight .. '.' .. lang
  if fn.hlexists(lang_highlight) == 1 and has_highlight_attributes(lang_highlight) then
    capture_highlight_cache[key] = lang_highlight
  elseif fn.hlexists(highlight) == 1 and has_highlight_attributes(highlight) then
    capture_highlight_cache[key] = highlight
  else
    capture_highlight_cache[key] = false
  end

  return capture_highlight_cache[key] or nil
end

local function resolve_syntax_highlight(line_num, col)
  local syntax_id = fn.synIDtrans(fn.synID(line_num, col, 1))
  local cached = syntax_highlight_cache[syntax_id]
  if cached ~= nil then
    return cached or nil
  end

  local name = fn.synIDattr(syntax_id, 'name')
  syntax_highlight_cache[syntax_id] = name ~= '' and has_highlight_attributes(name) and name or false
  return syntax_highlight_cache[syntax_id] or nil
end

local function add_span(spans, start_col, end_col, highlight, priority)
  if highlight == nil or start_col >= end_col then
    return
  end

  spans[#spans + 1] = {
    start_col = start_col,
    end_col = end_col,
    highlight = highlight,
    priority = priority,
    order = #spans + 1,
  }
end

local function collect_syntax_spans(spans, bufnr, line_num, line_text)
  if vim.bo[bufnr].syntax == '' then
    return
  end

  local max_col = vim.bo[bufnr].synmaxcol
  local scan_end = max_col > 0 and math.min(#line_text, max_col) or #line_text
  local current_highlight
  local span_start = 0

  for _, col in ipairs(vim.str_utf_pos(line_text)) do
    if col > scan_end then
      break
    end

    local highlight = resolve_syntax_highlight(line_num, col)
    local start_col = col - 1
    if highlight ~= current_highlight then
      add_span(spans, span_start, start_col, current_highlight, vim.hl.priorities.syntax)
      current_highlight = highlight
      span_start = start_col
    end
  end

  add_span(spans, span_start, scan_end, current_highlight, vim.hl.priorities.syntax)
end

local function get_query(lang)
  local cached = query_cache[lang]
  if cached ~= nil then
    return cached or nil
  end

  local ok, query = pcall(vim.treesitter.query.get, lang, 'highlights')
  query_cache[lang] = ok and query or false
  return query_cache[lang] or nil
end

local function get_buffer_state(bufnr)
  local tick = api.nvim_buf_get_changedtick(bufnr)
  local state = buffer_cache[bufnr]
  if state == nil or state.tick ~= tick then
    state = { tick = tick, lines = {}, parser_checked = false }
    buffer_cache[bufnr] = state
  end
  return state
end

local function get_parser(state, bufnr)
  if state.parser_checked then
    return state.parser
  end

  state.parser_checked = true
  local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
  state.parser = vim.treesitter.get_parser(bufnr, lang, { error = false })
  if state.parser and not pcall(state.parser.parse, state.parser) then
    state.parser = nil
  end
  return state.parser
end

local function capture_range_on_line(node, metadata, bufnr, row, line_length)
  local range = vim.treesitter.get_range(node, bufnr, metadata)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[4], range[5]
  if start_row > row or end_row < row or (end_row == row and end_col == 0) then
    return nil
  end

  start_col = start_row < row and 0 or start_col
  end_col = end_row > row and line_length or end_col
  start_col = math.max(0, math.min(start_col, line_length))
  end_col = math.max(start_col, math.min(end_col, line_length))
  return start_col, end_col
end

local function collect_treesitter_spans(spans, state, bufnr, line_num, line_text)
  local parser = get_parser(state, bufnr)
  if parser == nil then
    return
  end

  local row = line_num - 1
  pcall(function()
    parser:for_each_tree(function(tree, language_tree)
      local lang = language_tree:lang()
      local query = get_query(lang)
      if query == nil then
        return
      end

      for id, node, metadata in query:iter_captures(tree:root(), bufnr, row, row + 1) do
        local capture = query.captures[id]
        local highlight = resolve_capture_highlight(capture, lang)
        if highlight then
          local capture_metadata = metadata and metadata[id] or nil
          local start_col, end_col = capture_range_on_line(node, capture_metadata, bufnr, row, #line_text)
          if start_col then
            local priority = tonumber(
              (capture_metadata and capture_metadata.priority) or (metadata and metadata.priority)
            ) or TREESITTER_PRIORITY
            add_span(spans, start_col, end_col, highlight, priority)
          end
        end
      end
    end)
  end)
end

local function append_chunk(chunks, text, highlight)
  if text == '' then
    return
  end

  local last = chunks[#chunks]
  if last and last[2] == highlight then
    last[1] = last[1] .. text
  else
    chunks[#chunks + 1] = { text, highlight }
  end
end

local function spans_to_chunks(spans, line_text)
  local starts = {}
  local stops = {}
  local boundaries = { [0] = true, [#line_text] = true }

  for id, span in ipairs(spans) do
    boundaries[span.start_col] = true
    boundaries[span.end_col] = true
    starts[span.start_col] = starts[span.start_col] or {}
    stops[span.end_col] = stops[span.end_col] or {}
    starts[span.start_col][#starts[span.start_col] + 1] = id
    stops[span.end_col][#stops[span.end_col] + 1] = id
  end

  local positions = vim.tbl_keys(boundaries)
  table.sort(positions)

  local active = {}
  local chunks = {}
  for index = 1, #positions - 1 do
    local pos = positions[index]
    for _, id in ipairs(stops[pos] or {}) do
      active[id] = nil
    end
    for _, id in ipairs(starts[pos] or {}) do
      active[id] = spans[id]
    end

    local winner
    for _, span in pairs(active) do
      if
        winner == nil
        or span.priority > winner.priority
        or (span.priority == winner.priority and span.order > winner.order)
      then
        winner = span
      end
    end

    local next_pos = positions[index + 1]
    append_chunk(
      chunks,
      string.sub(line_text, pos + 1, next_pos),
      winner and winner.highlight or BASE_HIGHLIGHT
    )
  end

  return chunks
end

local function get_line_fold_chunks(bufnr, line_num)
  local state = get_buffer_state(bufnr)
  if state.lines[line_num] then
    return state.lines[line_num]
  end

  local line_text = api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)[1]
  if line_text == nil then
    return { { fn.foldtext(), 'Folded' } }
  end

  local spans = {}
  collect_syntax_spans(spans, bufnr, line_num, line_text)
  collect_treesitter_spans(spans, state, bufnr, line_num, line_text)

  local chunks = spans_to_chunks(spans, line_text)
  state.lines[line_num] = chunks
  return chunks
end

local function copy_chunks(target, source, trim_leading_space)
  for index, chunk in ipairs(source) do
    local text = chunk[1]
    if trim_leading_space and index == 1 then
      text = text:gsub('^%s+', '')
    end
    append_chunk(target, text, chunk[2])
  end
end

local function truncate_foldtext(chunks, leftcol)
  if leftcol == 0 then
    return chunks
  end

  local result = {}
  local remaining = leftcol
  local visible = false

  for _, chunk in ipairs(chunks) do
    local text = chunk[1]
    local highlight = chunk[2]
    if visible then
      append_chunk(result, text, highlight)
    else
      local width = fn.strwidth(text)
      if width <= remaining then
        remaining = remaining - width
      else
        local positions = vim.str_utf_pos(text)
        local consumed = 0
        for index, byte_col in ipairs(positions) do
          local next_byte = positions[index + 1] or (#text + 1)
          local char = text:sub(byte_col, next_byte - 1)
          local char_width = fn.strwidth(char)
          if consumed + char_width > remaining then
            if consumed < remaining then
              append_chunk(result, '>', 'Conceal')
              byte_col = next_byte
            end
            append_chunk(result, text:sub(byte_col), highlight)
            break
          end
          consumed = consumed + char_width
        end
        visible = true
      end
    end
  end

  return result
end

local function prefix_by_width(text, max_width)
  local width = fn.strwidth(text)
  if width <= max_width then
    return text, width
  end

  local positions = vim.str_utf_pos(text)
  local used = 0
  local end_byte = 0
  for index, byte_col in ipairs(positions) do
    local next_byte = positions[index + 1] or (#text + 1)
    local char_width = fn.strwidth(text:sub(byte_col, next_byte - 1))
    if used + char_width > max_width then
      break
    end
    used = used + char_width
    end_byte = next_byte - 1
  end
  return text:sub(1, end_byte), used
end

local function append_fold_count(chunks, foldstart, foldend)
  local suffix = (' 󰁂 %d '):format(foldend - foldstart)
  local ellipsis = '…'
  local text_width = 0
  for _, chunk in ipairs(chunks) do
    text_width = text_width + fn.strwidth(chunk[1])
  end

  local wininfo = fn.getwininfo(api.nvim_get_current_win())[1]
  local win_width = wininfo.width - wininfo.textoff
  local suffix_width = fn.strwidth(suffix)
  local padding = win_width - text_width - suffix_width

  if padding > 0 then
    append_chunk(chunks, string.rep(' ', padding), 'Folded')
  elseif padding < 0 then
    local max_text_width = math.max(0, win_width - suffix_width - fn.strwidth(ellipsis))
    local truncated = {}
    local used = 0
    for _, chunk in ipairs(chunks) do
      if used >= max_text_width then
        break
      end

      local text, width = prefix_by_width(chunk[1], max_text_width - used)
      append_chunk(truncated, text, chunk[2])
      used = used + width
      if #text < #chunk[1] then
        break
      end
    end
    append_chunk(truncated, ellipsis, 'Comment')
    chunks = truncated
  end

  append_chunk(chunks, suffix, 'Comment')
  return chunks
end

local function set_foldtext_highlights()
  local normal = api.nvim_get_hl(0, { name = 'Normal', link = false })
  local folded = api.nvim_get_hl(0, { name = 'Folded', link = false })
  api.nvim_set_hl(0, BASE_HIGHLIGHT, { fg = normal.fg, bg = folded.bg })
  api.nvim_set_hl(0, 'TSPunctBracket', { fg = '#ABB2BF' })
end

local function clear_highlight_caches()
  capture_highlight_cache = {}
  query_cache = {}
  syntax_highlight_cache = {}
  buffer_cache = {}
end

function M.custom_foldtext(foldstart, foldend)
  local bufnr = api.nvim_get_current_buf()
  local chunks = {}
  copy_chunks(chunks, get_line_fold_chunks(bufnr, foldstart), false)

  if should_append_end_line(bufnr) then
    append_chunk(chunks, ' … ', 'TSPunctBracket')
    copy_chunks(chunks, get_line_fold_chunks(bufnr, foldend), true)
  end

  return truncate_foldtext(chunks, fn.winsaveview().leftcol)
end

function M.apply_treesitter_fold(bufnr, win_id)
  vim.schedule(function()
    if not api.nvim_win_is_valid(win_id) or api.nvim_win_get_buf(win_id) ~= bufnr then
      return
    end

    vim.wo[win_id].foldmethod = 'expr'
    vim.wo[win_id].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo[win_id].foldtext = 'v:lua.__custom_foldtext()'
  end)
end

local function apply_to_buffer_windows(bufnr)
  attached_buffers[bufnr] = true
  buffer_cache[bufnr] = nil
  for _, win_id in ipairs(fn.win_findbuf(bufnr)) do
    M.apply_treesitter_fold(bufnr, win_id)
  end
end

function M.setup()
  local group = api.nvim_create_augroup('Lu5je0Fold', { clear = true })

  _G.__custom_foldtext = function()
    local foldstart = vim.v.foldstart
    local foldend = vim.v.foldend
    return append_fold_count(M.custom_foldtext(foldstart, foldend), foldstart, foldend)
  end

  set_foldtext_highlights()
  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      clear_highlight_caches()
      set_foldtext_highlights()
    end,
  })

  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'TreesitterAttach',
    callback = function(args)
      apply_to_buffer_windows(args.buf)
    end,
  })

  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'TSUpdate',
    callback = clear_highlight_caches,
  })

  api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    callback = function(args)
      if attached_buffers[args.buf] then
        M.apply_treesitter_fold(args.buf, api.nvim_get_current_win())
      end
    end,
  })

  api.nvim_create_autocmd('Syntax', {
    group = group,
    callback = function(args)
      buffer_cache[args.buf] = nil
    end,
  })

  api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      buffer_cache[args.buf] = nil
      attached_buffers[args.buf] = nil
    end,
  })
end

return M
