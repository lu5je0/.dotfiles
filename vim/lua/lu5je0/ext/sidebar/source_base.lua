-- Common scaffolding for a sidebar source (a tab's data + UI behaviour).
--
-- A source is described by a spec table; this module wraps it with the
-- shared render → flush pipeline and the open_node/close_node glue,
-- so each concrete source only writes the parts that genuinely differ.
--
-- Spec API (all optional unless noted):
--   id          string                            (required, matches config.tabs)
--   state_key   string                            (defaults to id; key under state.<x>)
--   build       (state_tab) -> roots, header      header is { lines, items, highlights } or nil
--   render_opts (state_tab, ctx) -> opts          opts table forwarded to render.render_tree
--   decorate    (state_tab, lines, items, hls,    optional, may mutate in place OR
--                vt, ctx) -> [lines, items,       return replacement tuples (rebuild)
--                            hls, vt]
--   post_flush  (state_tab, ctx)                  optional, runs AFTER display_items
--                                                 and buffer have been flushed
--   open        { is_expandable, is_expanded,
--                 expand, on_already_expanded,
--                 on_file }                       used by open_node()
--   close       { is_closeable, close,
--                 is_boundary }                   used by close_node()
--   keymaps     () -> list                        per-tab keymaps
--
local render = require('lu5je0.ext.sidebar.render')
local view = require('lu5je0.ext.sidebar.view')
local state = require('lu5je0.ext.sidebar.state')

local M = {}

local function tab_state(spec)
  return state[spec.state_key or spec.id]
end

local function merge_offset(offset, list, key)
  if offset == 0 then return end
  for _, v in ipairs(list) do v[key] = v[key] + offset end
end

--- Run the full render pipeline for a source.
--- @param spec table
--- @param ctx  table|nil  — extra context forwarded to spec hooks (e.g. { reveal_path = X })
function M.render(spec, ctx)
  ctx = ctx or {}
  local ts = tab_state(spec)

  local roots, header = spec.build(ts, ctx)
  roots = roots or {}
  header = header or { lines = {}, items = {}, highlights = {} }

  local opts = spec.render_opts and spec.render_opts(ts, ctx) or {}
  local lines, items, highlights, virt_texts = render.render_tree(roots, opts)

  -- Splice header in front, offsetting tree indices.
  if #header.lines > 0 then
    local offset = #header.lines
    merge_offset(offset, items, 'line_idx')
    merge_offset(offset, highlights, 'line')
    merge_offset(offset, virt_texts, 'line')

    local merged = {}
    for _, l in ipairs(header.lines) do merged[#merged + 1] = l end
    for _, l in ipairs(lines) do merged[#merged + 1] = l end
    lines = merged

    local mi = {}
    for _, it in ipairs(header.items) do mi[#mi + 1] = it end
    for _, it in ipairs(items) do mi[#mi + 1] = it end
    items = mi

    local mh = {}
    for _, h in ipairs(header.highlights) do mh[#mh + 1] = h end
    for _, h in ipairs(highlights) do mh[#mh + 1] = h end
    highlights = mh
  end

  if spec.decorate then
    local nl, ni, nh, nv = spec.decorate(ts, lines, items, highlights, virt_texts, ctx)
    if nl then lines = nl end
    if ni then items = ni end
    if nh then highlights = nh end
    if nv then virt_texts = nv end
  end

  ts.display_items = items
  view.flush(lines, highlights, virt_texts)

  if spec.post_flush then
    spec.post_flush(ts, ctx)
  end
end

--- open_node glue using the source's `open` spec.
function M.open_node(spec, render_fn)
  local ts = tab_state(spec)
  local glue = spec.open or {}
  view.open_node({
    get_items = function() return ts.display_items end,
    render_fn = render_fn,
    is_expandable = glue.is_expandable,
    is_expanded = glue.is_expanded,
    expand = glue.expand,
    on_already_expanded = glue.on_already_expanded,
    on_file = glue.on_file,
  })
end

--- close_node glue using the source's `close` spec.
function M.close_node(spec, render_fn)
  local ts = tab_state(spec)
  local glue = spec.close or {}
  view.close_node({
    get_items = function() return ts.display_items end,
    render_fn = render_fn,
    is_closeable = glue.is_closeable,
    close = glue.close,
    is_boundary = glue.is_boundary,
  })
end

return M
