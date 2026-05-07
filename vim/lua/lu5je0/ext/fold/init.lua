local M = {}

local fold_suffix_filetypes = { 'lua', 'java', 'json', 'xml', 'rust', 'html', 'c', 'cpp' }

local function should_show_fold_suffix(bufnr)
  return vim.tbl_contains(fold_suffix_filetypes, vim.bo[bufnr].filetype)
end

local function fallback_fold_text()
  return { { vim.fn.foldtext(), 'Folded' } }
end

local function resolve_capture_highlight(capture, lang)
  local highlight = '@' .. capture
  local lang_highlight = highlight .. '.' .. lang
  if vim.fn.hlexists(lang_highlight) == 1 then
    return lang_highlight
  end
  return highlight
end

local function merge_highlight_spans(spans, line_text)
  table.insert(spans, 1, { text = line_text, pos = { 0, #line_text }, highlight = 'Folded' })

  local merged = {}

  for _, span in ipairs(spans) do
    local span_start = span.pos[1]
    local span_end = span.pos[2]
    local next_merged = {}

    for _, merged_span in ipairs(merged) do
      local merged_start = merged_span.pos[1]
      local merged_end = merged_span.pos[2]

      if span_start >= merged_end or span_end <= merged_start then
        table.insert(next_merged, merged_span)
      else
        if merged_start < span_start then
          table.insert(next_merged, {
            highlight = merged_span.highlight,
            pos = { merged_start, span_start },
            text = string.sub(merged_span.text, 1, span_start - merged_start),
          })
        end

        if merged_end > span_end then
          table.insert(next_merged, {
            highlight = merged_span.highlight,
            pos = { span_end, merged_end },
            text = string.sub(merged_span.text, span_end - merged_start + 1, merged_end - merged_start),
          })
        end
      end
    end

    table.insert(next_merged, {
      highlight = span.highlight,
      pos = { span_start, span_end },
      text = span.text,
    })

    table.sort(next_merged, function(a, b)
      return a.pos[1] < b.pos[1]
    end)

    merged = next_merged
  end

  return merged
end

local function get_line_fold_chunks(bufnr, line_num)
  local line_text = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)[1]
  if line_text == nil then
    return fallback_fold_text()
  end

  local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
  local parser = vim.treesitter.get_parser(bufnr, lang, { error = false })
  if parser == nil then
    return fallback_fold_text()
  end

  local query = vim.treesitter.query.get(parser:lang(), 'highlights')
  if query == nil then
    return { { line_text, 'Folded' } }
  end

  local tree = parser:parse({ line_num - 1, line_num })[1]
  if tree == nil then
    return fallback_fold_text()
  end

  local spans = {}
  for id, node in query:iter_captures(tree:root(), bufnr, line_num - 1, line_num) do
    local start_row, start_col, end_row, end_col = node:range()
    if start_row == line_num - 1 and end_row == line_num - 1 and start_col and end_col then
      table.insert(spans, {
        text = vim.treesitter.get_node_text(node, bufnr),
        pos = { start_col, end_col },
        highlight = resolve_capture_highlight(query.captures[id], lang),
      })
    end
  end

  local chunks = {}
  for _, span in ipairs(merge_highlight_spans(spans, line_text)) do
    if not string.match(span.text, '\n') then -- xml 有时会产生包含换行的空片段
      table.insert(chunks, { span.text, span.highlight })
    end
  end

  return chunks
end

local function truncate_foldtext(chunks, leftcol)
  if leftcol == 0 then
    return chunks
  end

  local result = {}
  local foldtext_col = 0
  local found = false

  for _, chunk in ipairs(chunks) do
    local text = chunk[1]
    local hl = chunk[2]

    for i = 1, vim.fn.strchars(text) do
      local c = vim.fn.strcharpart(text, i - 1, 1)
      local width = vim.fn.strwidth(c)
      foldtext_col = foldtext_col + width
      if foldtext_col > leftcol then
        if width == 1 or (width > 1 and foldtext_col - leftcol == 2) then
          table.insert(result, { vim.fn.strcharpart(text, i - 1), hl })
        else
          table.insert(result, { '>', 'Conceal' })
          table.insert(result, { vim.fn.strcharpart(text, i), hl })
        end
        found = true
        goto continue
      end
    end

    if found then
      table.insert(result, chunk)
    end

    ::continue::
  end

  return result
end

local function set_foldtext_highlights()
  vim.api.nvim_set_hl(0, 'TSPunctBracket', { fg = '#ABB2BF' })
end

function M.custom_foldtext(foldstart, foldend)
  local bufnr = vim.api.nvim_get_current_buf()
  local chunks = get_line_fold_chunks(bufnr, foldstart)

  if should_show_fold_suffix(bufnr) then
    table.insert(chunks, { ' … ', 'TSPunctBracket' })
    for i, chunk in ipairs(get_line_fold_chunks(bufnr, foldend)) do
      if i == 1 then
        chunk[1] = chunk[1]:gsub('^%s+', '')
      end
      table.insert(chunks, chunk)
    end
  end

  return truncate_foldtext(chunks, vim.fn.winsaveview().leftcol)
end

function M.apply_treesitter_fold(bufnr, win_id)
  vim.defer_fn(function()
    if not vim.api.nvim_win_is_valid(win_id) or vim.api.nvim_win_get_buf(win_id) ~= bufnr then
      return
    end

    vim.wo[win_id].foldmethod = 'expr'
    vim.wo[win_id].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo[win_id].foldtext = should_show_fold_suffix(bufnr) and 'v:lua.__custom_foldtext()' or ''
  end, 100)
end

local function setup_fold_text_cache()
  local foldtext_cache = {}

  local cached_fold_text = function()
    local foldstart = vim.v.foldstart
    local foldend = vim.v.foldend
    local win_id = vim.api.nvim_get_current_win()
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    local cache = foldtext_cache

    if
      cache[win_id]
      and cache[win_id][buf_id]
      and cache[win_id][buf_id][foldstart]
      and cache[win_id][buf_id][foldstart][foldend]
    then
      return cache[win_id][buf_id][foldstart][foldend]
    end

    local text = M.custom_foldtext(foldstart, foldend)

    cache[win_id] = cache[win_id] or {}
    cache[win_id][buf_id] = cache[win_id][buf_id] or {}
    cache[win_id][buf_id][foldstart] = cache[win_id][buf_id][foldstart] or {}
    cache[win_id][buf_id][foldstart][foldend] = text

    return text
  end

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout', 'TextChanged', 'TextChangedI' }, {
    callback = require('lu5je0.lang.function-utils').throttle(function(args)
      local buf_id = args.buf
      for win_id, win_data in pairs(foldtext_cache) do
        if win_data[buf_id] then
          win_data[buf_id] = nil
          if next(win_data) == nil then
            foldtext_cache[win_id] = nil
          end
        end
      end
    end, 100),
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    callback = function(args)
      local win_id = tonumber(args.match)
      if win_id then
        foldtext_cache[win_id] = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinScrolled', {
    callback = function(args)
      local win_id = tonumber(args.match)
      if win_id then
        foldtext_cache[win_id] = nil
      end
    end,
  })

  _G.__custom_foldtext = cached_fold_text
end

function M.setup()
  _G.__custom_foldtext = function()
    return M.custom_foldtext(vim.v.foldstart, vim.v.foldend)
  end

  set_foldtext_highlights()
  vim.api.nvim_create_autocmd('ColorScheme', {
    callback = set_foldtext_highlights,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'TreesitterAttach',
    callback = function(args)
      M.apply_treesitter_fold(args.buf, vim.api.nvim_get_current_win())
    end,
  })

  setup_fold_text_cache()
end

return M
