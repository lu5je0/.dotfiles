local api = vim.api
local ns = api.nvim_create_namespace('git_unified_diff')
local views = {}

local M = {}

local function apply_highlights()
  local normal = api.nvim_get_hl(0, { name = 'Normal', link = false })
  local added = api.nvim_get_hl(0, { name = 'DiffAdd', link = false })
  local removed = api.nvim_get_hl(0, { name = 'DiffDelete', link = false })
  api.nvim_set_hl(0, 'GitUnifiedDiffCode', { fg = normal.fg, ctermfg = normal.ctermfg })
  api.nvim_set_hl(0, 'GitUnifiedDiffAdded', { bg = added.bg, ctermbg = added.ctermbg })
  api.nvim_set_hl(0, 'GitUnifiedDiffRemoved', { bg = removed.bg, ctermbg = removed.ctermbg })
end

apply_highlights()
api.nvim_create_autocmd('ColorScheme', {
  group = api.nvim_create_augroup('GitUnifiedDiffHighlight', { clear = true }),
  callback = apply_highlights,
})

local function map_lines(lines, sources)
  local rows, used_sources = {}, {}
  local old_row, new_row
  for index = 3, #lines do
    local line = lines[index]
    local old, new = line:match('^@@ %-(%d+)[^ ]* %+(%d+)[^ ]* @@')
    if old then
      old_row, new_row = tonumber(old), tonumber(new)
    elseif old_row then
      local prefix = line:sub(1, 1)
      if prefix == '-' then
        rows[index] = { sources[1], old_row, 'GitUnifiedDiffRemoved' }
        used_sources[1] = true
        old_row = old_row + 1
      elseif prefix == '+' or prefix == ' ' then
        rows[index] = { sources[2], new_row, prefix == '+' and 'GitUnifiedDiffAdded' or nil }
        used_sources[2] = true
        new_row = new_row + 1
        if prefix == ' ' then
          old_row = old_row + 1
        end
      end
    end
  end
  return rows, used_sources
end

local function parse_source(source, redraw)
  if source.started or source.kind ~= 'text' or #source.lines == 0 then
    return
  end
  source.started = true
  local ft = vim.filetype.match { filename = source.filename }
  if not ft then
    return
  end
  local lang = vim.treesitter.language.get_lang(ft)
  source.text = source.text or (table.concat(source.lines, '\n') .. '\n')
  local ok, parser = pcall(vim.treesitter.get_string_parser, source.text, lang)
  if not ok then
    return
  end

  pcall(parser.parse, parser, true, function(err)
    if err then
      return
    end
    source.trees, source.highlights = {}, {}
    parser:for_each_tree(function(tree, language_tree)
      local tree_lang = language_tree:lang()
      local has_query, query = pcall(vim.treesitter.query.get, tree_lang, 'highlights')
      if has_query and query then
        source.trees[#source.trees + 1] = { tree:root(), query, tree_lang }
      end
    end)
    redraw()
  end)
end

local function line_highlights(source, line_num)
  local cached = source.highlights[line_num]
  if cached then
    return cached
  end
  local spans = {}
  local row = line_num - 1
  local width = #(source.lines[line_num] or '')
  for _, entry in ipairs(source.trees) do
    local root, query, lang = unpack(entry)
    for id, node, metadata in query:iter_captures(root, source.text, row, row + 1) do
      local capture = query.captures[id]
      if capture:sub(1, 1) ~= '_' then
        local match = metadata[id]
        local range = vim.treesitter.get_range(node, source.text, match)
        local first_row, first_col, last_row, last_col = range[1], range[2], range[4], range[5]
        if first_row <= row and row <= last_row then
          local start = first_row == row and math.max(0, first_col) or 0
          local stop = last_row == row and math.min(width, last_col) or width
          if start < stop then
            spans[#spans + 1] = {
              start + 1, -- Leave the diff prefix in its original color.
              stop + 1,
              '@' .. capture .. '.' .. lang,
              tonumber(metadata.priority or (match and match.priority)) or vim.hl.priorities.treesitter,
            }
          end
        end
      end
    end
  end
  source.highlights[line_num] = spans
  return spans
end

api.nvim_set_decoration_provider(ns, {
  on_win = function(_, _, buf)
    local view = views[buf]
    if not view then
      return false
    end
    if view.parse then
      vim.schedule(view.parse)
      view.parse = nil
    end
  end,
  on_range = function(_, _, buf, first, _, last, end_col)
    local view = views[buf]
    for line_num = first + 1, last + (end_col > 0 and 1 or 0) do
      local location = view.rows[line_num]
      if location then
        local source, source_line, background = unpack(location)
        if background then
          api.nvim_buf_set_extmark(buf, ns, line_num - 1, 0, {
            end_row = line_num,
            end_col = 0,
            hl_group = background,
            hl_eol = true,
            priority = vim.hl.priorities.treesitter + 1,
            ephemeral = true,
          })
          local width = #(source.lines[source_line] or '')
          if width > 0 then
            api.nvim_buf_set_extmark(buf, ns, line_num - 1, 1, {
              end_col = width + 1,
              hl_group = 'GitUnifiedDiffCode',
              priority = vim.hl.priorities.syntax + 1,
              ephemeral = true,
            })
          end
        end
        if source.trees then
          for _, span in ipairs(line_highlights(source, source_line)) do
            api.nvim_buf_set_extmark(buf, ns, line_num - 1, span[1], {
              end_col = span[2],
              hl_group = span[3],
              priority = span[4],
              ephemeral = true,
            })
          end
        end
      end
    end
  end,
})

local function same_source(a, b)
  return a.lines == b.lines and a.filename == b.filename and a.kind == b.kind
end

function M.apply(buf, lines, sources)
  local previous = views[buf]
  if previous then
    -- Context toggles change the patch, while both snapshots stay the same.
    if same_source(previous.sources[1], sources[1]) and same_source(previous.sources[2], sources[2]) then
      sources = previous.sources
    end
  else
    api.nvim_buf_attach(buf, false, {
      on_detach = function()
        views[buf] = nil
      end,
    })
  end
  local rows, used_sources = map_lines(lines, sources)
  local view = { rows = rows, sources = sources }
  views[buf] = view
  local function redraw()
    local current = views[buf]
    if current and current.sources == sources and api.nvim_buf_is_loaded(buf) then
      api.nvim__redraw { buf = buf, valid = false }
    end
  end

  -- Keep the patch visible while the original files are parsed.
  function view.parse()
    if views[buf] ~= view then
      return
    end
    for index, source in ipairs(sources) do
      if used_sources[index] then
        parse_source(source, redraw)
      end
    end
  end
end

return M
