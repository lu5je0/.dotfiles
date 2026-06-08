-- Symbols source: LSP documentSymbol tree with treesitter fallback.
local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local source_base = require('lu5je0.ext.tree-sidebar.source_base')
local view = require('lu5je0.ext.tree-sidebar.view')
local env_keeper = require('lu5je0.misc.env-keeper')

local M = {}

local function get_icon(kind)
  local entry = config.symbols.icons[kind]
  if entry then return entry.icon, entry.hl end
  return '', 'Normal'
end

local function lsp_symbols_to_tree(symbols, old_nodes)
  local old_map = {}
  if old_nodes then
    local old_count = {}
    for _, n in ipairs(old_nodes) do
      local base = n.name .. ':' .. (n.kind or 0)
      old_count[base] = (old_count[base] or 0) + 1
      old_map[base .. ':' .. old_count[base]] = n
    end
  end

  local nodes = {}
  local new_count = {}
  for _, sym in ipairs(symbols) do
    local base = sym.name .. ':' .. (sym.kind or 0)
    new_count[base] = (new_count[base] or 0) + 1
    local key = base .. ':' .. new_count[base]
    local old = old_map[key]
    local node = {
      name = sym.name,
      type = (sym.children and #sym.children > 0) and 'directory' or 'file',
      kind = sym.kind,
      range = sym.range or (sym.location and sym.location.range),
      selection_range = sym.selectionRange,
      detail = sym.detail,
      expanded = old and old.expanded or false,
    }
    if sym.children and #sym.children > 0 then
      node.children = lsp_symbols_to_tree(sym.children, old and old.children or nil)
    end
    nodes[#nodes + 1] = node
  end
  return nodes
end

-- ── treesitter backend ─────────────────────────────────

local ts_query_defs = {
  markdown = {
    { query = '(section (atx_heading (_) (inline) @name)) @symbol', kind = 15 },
  },
}

local ts_query_cache = {}
local function get_ts_queries(filetype)
  if ts_query_cache[filetype] then return ts_query_cache[filetype] end
  local defs = ts_query_defs[filetype]
  if not defs then return nil end
  local compiled = {}
  for _, def in ipairs(defs) do
    local ok, query = pcall(vim.treesitter.query.parse, filetype, def.query)
    if ok then
      compiled[#compiled + 1] = { query = query, kind = def.kind }
    end
  end
  ts_query_cache[filetype] = compiled
  return compiled
end

local function build_old_map(old_nodes)
  local map = {}
  if not old_nodes then return map end
  local count = {}
  for _, n in ipairs(old_nodes) do
    local base = n.name .. ':' .. (n.kind or 0)
    count[base] = (count[base] or 0) + 1
    map[base .. ':' .. count[base]] = n
  end
  return map
end

local function range_contains(outer, inner)
  if outer.start.line == inner.start.line and outer.start.character == inner.start.character
    and outer['end'].line == inner['end'].line and outer['end'].character == inner['end'].character then
    return false
  end
  if outer.start.line > inner.start.line then return false end
  if outer['end'].line < inner['end'].line then return false end
  if outer.start.line == inner.start.line and outer.start.character > inner.start.character then return false end
  if outer['end'].line == inner['end'].line and outer['end'].character < inner['end'].character then return false end
  return true
end

local function insert_into_tree(roots, sym)
  for i = #roots, 1, -1 do
    local r = roots[i]
    if r.range and sym.range and range_contains(r.range, sym.range) then
      if not r.children then r.children = {} end
      r.type = 'directory'
      insert_into_tree(r.children, sym)
      return
    end
  end
  roots[#roots + 1] = sym
end

local function restore_expanded(nodes, old_map)
  local count = {}
  for _, node in ipairs(nodes) do
    local base = node.name .. ':' .. (node.kind or 0)
    count[base] = (count[base] or 0) + 1
    local old = old_map[base .. ':' .. count[base]]
    if old then
      node.expanded = old.expanded
    end
    if node.children then
      local child_old_map = old and build_old_map(old.children) or {}
      restore_expanded(node.children, child_old_map)
    end
  end
end

local function treesitter_symbols_to_tree(bufnr, filetype, old_nodes)
  local rules = get_ts_queries(filetype)
  if not rules or #rules == 0 then return {} end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, filetype)
  if not ok or not parser then return {} end

  local trees = parser:parse()
  if not trees or #trees == 0 then return {} end
  local root = trees[1]:root()

  local flat = {}
  for _, rule in ipairs(rules) do
    local query = rule.query
    for _, match in query:iter_matches(root, bufnr) do
      local sym_node, name_node
      for id, nodes in pairs(match) do
        local cap = query.captures[id]
        local node = type(nodes) == 'table' and nodes[1] or nodes
        if cap == 'symbol' then sym_node = node
        elseif cap == 'name' then name_node = node
        end
      end
      if sym_node and name_node then
        local sr1, sc1, sr2, sc2 = sym_node:range()
        local nr1, nc1, nr2, nc2 = name_node:range()
        flat[#flat + 1] = {
          name = vim.treesitter.get_node_text(name_node, bufnr):gsub('\n.*', ''),
          kind = rule.kind,
          range = { start = { line = sr1, character = sc1 }, ['end'] = { line = sr2, character = sc2 } },
          selection_range = { start = { line = nr1, character = nc1 }, ['end'] = { line = nr2, character = nc2 } },
        }
      end
    end
  end

  table.sort(flat, function(a, b)
    if a.range.start.line ~= b.range.start.line then
      return a.range.start.line < b.range.start.line
    end
    return a.range.start.character < b.range.start.character
  end)

  local roots = {}
  for _, sym in ipairs(flat) do
    sym.type = 'file'
    sym.expanded = false
    insert_into_tree(roots, sym)
  end

  local old_map = build_old_map(old_nodes)
  restore_expanded(roots, old_map)

  return roots
end

-- ── source spec ─────────────────────────────────────────

local function mark_leaf_indent(children)
  if not children then return end
  local has_dir = false
  for _, n in ipairs(children) do
    if n.type == 'directory' then has_dir = true; break end
  end
  for _, n in ipairs(children) do
    n._indent_leaf = has_dir
    if n.children then mark_leaf_indent(n.children) end
  end
end

local spec = { id = 'symbols', state_key = 'symbols' }
M._spec = spec

function spec.build(ts, _ctx)
  local nodes = ts.nodes or {}
  if #nodes == 0 then ts._is_empty = true; return {} end
  ts._is_empty = false
  mark_leaf_indent(nodes)
  return nodes
end

function spec.render_opts(_ts, _ctx)
  return {
    get_dir_icon = function(node)
      local icon = (get_icon(node.kind))
      local arrow = node.expanded and config.symbols.arrow_icons.expanded or config.symbols.arrow_icons.collapsed
      return arrow .. ' ' .. icon
    end,
    get_file_icon = function(node)
      local icon, hl = get_icon(node.kind)
      if node._indent_leaf then return '  ' .. icon, hl end
      return icon, hl
    end,
    file_suffix = function(node)
      if node.detail and node.detail ~= '' then return node.detail, 'Comment' end
    end,
    dir_suffix = function(node)
      if node.detail and node.detail ~= '' then return node.detail, 'Comment' end
    end,
    item_data = function(node)
      return { kind = node.kind, range = node.range, selection_range = node.selection_range }
    end,
  }
end

function spec.decorate(ts, lines, items, highlights, virt_texts, _ctx)
  if ts._is_empty then
    return { '  No symbols' }, {}, {}, {}
  end

  -- Override folder icon highlight with the kind-specific group.
  for _, h in ipairs(highlights) do
    if h.hl == 'TreeSidebarFolderIcon' then
      local item = items[h.line + 1]
      if item and item.kind then
        local _, hl = get_icon(item.kind)
        h.hl = hl
      end
    end
  end

  for _, vt in ipairs(virt_texts) do vt.pos = 'eol' end
end

function M.render()
  source_base.render(spec)
end

-- ── symbol query ───────────────────────────────────────

function M.request_symbols(opts)
  opts = opts or {}
  local tabpage = vim.api.nvim_get_current_tabpage()
  local ts = state.tab_for(tabpage)

  local target_buf, target_win = nil, nil

  local source_win = opts.source_win
  if source_win and vim.api.nvim_win_is_valid(source_win) and source_win ~= ts.win then
    local buf = vim.api.nvim_win_get_buf(source_win)
    if vim.bo[buf].buftype == '' and vim.bo[buf].buflisted then
      target_buf = buf; target_win = source_win
    end
  end

  if not target_buf then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      if win ~= ts.win then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == '' and vim.bo[buf].buflisted then
          target_buf = buf; target_win = win; break
        end
      end
    end
  end
  if not target_buf then
    ts.symbols.nodes = {}
    ts.symbols.target_buf = nil
    if vim.api.nvim_get_current_tabpage() == tabpage then M.render() end
    return
  end

  local cursor_line = nil
  if opts.locate and target_win then
    cursor_line = vim.api.nvim_win_get_cursor(target_win)[1] - 1
  end

  -- Try LSP first.
  local clients = vim.lsp.get_clients({ bufnr = target_buf })
  local has_provider = false
  for _, client in ipairs(clients) do
    if client.server_capabilities.documentSymbolProvider then
      has_provider = true; break
    end
  end

  if has_provider then
    ts.symbols.target_buf = target_buf
    local params = { textDocument = vim.lsp.util.make_text_document_params(target_buf) }
    vim.lsp.buf_request(target_buf, 'textDocument/documentSymbol', params, function(err, result)
      if err or not result then
        ts.symbols.nodes = {}
        vim.schedule(function()
          if vim.api.nvim_get_current_tabpage() ~= tabpage then return end
          if ts.active_tab_idx == config.tab_idx('symbols') then M.render() end
        end)
        return
      end
      ts.symbols.nodes = lsp_symbols_to_tree(result, ts.symbols.nodes)
      vim.schedule(function()
        if vim.api.nvim_get_current_tabpage() ~= tabpage then return end
        if ts.active_tab_idx ~= config.tab_idx('symbols') then return end
        M.render()
        if cursor_line and state:is_open() then
          M.locate_by_line(cursor_line, { force = true })
        end
      end)
    end)
    return
  end

  -- Treesitter fallback.
  local ft = vim.bo[target_buf].filetype
  if vim.tbl_contains(config.symbols.treesitter_filetypes, ft) then
    ts.symbols.nodes = treesitter_symbols_to_tree(target_buf, ft, ts.symbols.nodes)
    ts.symbols.target_buf = target_buf
    if vim.api.nvim_get_current_tabpage() == tabpage then
      if ts.active_tab_idx == config.tab_idx('symbols') then
        M.render()
        if cursor_line and state:is_open() then
          M.locate_by_line(cursor_line, { force = true })
        end
      end
    end
    return
  end

  -- No provider available.
  ts.symbols.nodes = {}
  ts.symbols.target_buf = nil
  if vim.api.nvim_get_current_tabpage() == tabpage then M.render() end
end

local function expand_to_line(nodes, cursor_line, target_node)
  if not nodes then return false end
  for _, node in ipairs(nodes) do
    local r = node.range
    if r and cursor_line >= r.start.line and cursor_line <= r['end'].line then
      if node.type == 'directory' and node.children then
        if node ~= target_node then
          node.expanded = true
        end
        expand_to_line(node.children, cursor_line, target_node)
      end
      return true
    end
  end
  return false
end

local function collapse_all_nodes(nodes)
  if not nodes then return end
  for _, node in ipairs(nodes) do
    node.expanded = false
    if node.children then collapse_all_nodes(node.children) end
  end
end

local function same_node(a, b)
  if a == b then return true end
  if not a or not b then return false end
  if a.name ~= b.name or a.kind ~= b.kind then return false end
  if not a.range or not b.range then return false end
  return a.range.start.line == b.range.start.line
end

function M.locate_by_line(cursor_line, opts)
  opts = opts or {}
  if not state.symbols.nodes or #state.symbols.nodes == 0 then return end

  -- Find target node first (cheap traversal, no mutation).
  local function find_best_node(nodes)
    if not nodes then return nil end
    for _, node in ipairs(nodes) do
      local r = node.range
      if r and cursor_line >= r.start.line and cursor_line <= r['end'].line then
        if node.children and #node.children > 0 then
          local deeper = find_best_node(node.children)
          if deeper then return deeper end
        end
        return node
      end
    end
  end
  local target = find_best_node(state.symbols.nodes)
  if not target or (same_node(target, state.symbols.last_located_node) and not opts.force) then return end
  state.symbols.last_located_node = target

  if M.is_auto_follow() then
    collapse_all_nodes(state.symbols.nodes)
  end
  expand_to_line(state.symbols.nodes, cursor_line, target)
  M.render()

  local items = state.symbols.display_items
  if not items or #items == 0 then return end
  for i, item in ipairs(items) do
    if item.node == target then
      pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
      if not opts.no_center then
        vim.api.nvim_win_call(state.win, function()
          vim.cmd('normal! zz')
        end)
      end
      return
    end
  end
end

-- ── open ────────────────────────────────────────────────

function M.open_symbol()
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.symbols.display_items[line]
  if not item then return end
  local range = item.selection_range or item.range
  if not range then return end

  local target_buf = state.symbols.target_buf
  local target_win = nil
  if target_buf then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())) do
      if vim.api.nvim_win_get_buf(win) == target_buf then target_win = win; break end
    end
  end

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  else
    local target = require('lu5je0.ext.tree-sidebar.window').get_target_win()
    if target then
      vim.api.nvim_set_current_win(target)
    else
      vim.cmd('belowright vsplit')
    end
  end

  pcall(vim.api.nvim_win_set_cursor, 0, { range.start.line + 1, range.start.character })
end

function M.toggle_node()
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.symbols.display_items[line]
  if not item or not item.node then return end
  if item.node.type == 'directory' then
    item.node.expanded = not item.node.expanded
    M.render()
    pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
  else
    M.open_symbol()
  end
end

spec.close = {
  is_closeable = function(item)
    return item.node and item.node.type == 'directory' and item.node.expanded
  end,
  close = function(item) item.node.expanded = false end,
}

function M.close_node()
  source_base.close_node(spec, M.render)
end

function M.collapse_all()
  local old_items = state.symbols.display_items or {}
  local function collapse(nodes)
    if not nodes then return end
    for _, node in ipairs(nodes) do
      node.expanded = false
      if node.children then collapse(node.children) end
    end
  end
  collapse(state.symbols.nodes)
  M.render()
  view.restore_cursor(old_items, state.symbols.display_items)
end

function M.expand_all()
  local old_items = state.symbols.display_items or {}
  local function expand(nodes)
    if not nodes then return end
    for _, node in ipairs(nodes) do
      if node.children and #node.children > 0 then
        node.expanded = true
        expand(node.children)
      end
    end
  end
  expand(state.symbols.nodes)
  M.render()
  view.restore_cursor(old_items, state.symbols.display_items)
end

function M.is_auto_follow()
  if state.symbols.auto_follow == nil then
    state.symbols.auto_follow = env_keeper.get('symbols_auto_follow', true)
  end
  return state.symbols.auto_follow
end

function M.toggle_auto_follow()
  state.symbols.auto_follow = not M.is_auto_follow()
  env_keeper.set('symbols_auto_follow', state.symbols.auto_follow)
  vim.notify('Symbols auto-follow: ' .. (state.symbols.auto_follow and 'on' or 'off'), vim.log.levels.INFO)
end

function M.keymaps()
  return {
    { 'l', M.toggle_node, desc = 'Expand node' },
    { 'zo', M.toggle_node, desc = 'Expand node' },
    { 'h', M.close_node, desc = 'Collapse node' },
    { 'zc', M.close_node, desc = 'Collapse node' },
    { '<cr>', M.open_symbol, desc = 'Go to symbol' },
    { 'r', M.request_symbols, desc = 'Refresh' },
    { 'gf', M.toggle_auto_follow, desc = 'Toggle auto-follow' },
  }
end

return M
