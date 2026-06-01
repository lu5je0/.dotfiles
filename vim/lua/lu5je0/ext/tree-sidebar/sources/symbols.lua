local state = require('lu5je0.ext.tree-sidebar.state')
local render = require('lu5je0.ext.tree-sidebar.render')

local M = {}

local symbol_icons = {
  [1] = { icon = '󰈔', hl = 'Type' }, -- File
  [2] = { icon = '󰆧', hl = 'Include' }, -- Module
  [3] = { icon = '󰅩', hl = 'Include' }, -- Namespace
  [4] = { icon = '󰏗', hl = 'Type' }, -- Package
  [5] = { icon = '󱡠', hl = 'Type' }, -- Class
  [6] = { icon = '󰊕', hl = 'Function' }, -- Method
  [7] = { icon = '󰆧', hl = 'Constant' }, -- Property
  [8] = { icon = '󰆨', hl = 'Constant' }, -- Field
  [9] = { icon = '󰊕', hl = 'Function' }, -- Constructor
  [10] = { icon = '󰕘', hl = 'Type' }, -- Enum
  [11] = { icon = '󰜰', hl = 'Type' }, -- Interface
  [12] = { icon = '󰊕', hl = 'Function' }, -- Function
  [13] = { icon = '󰆦', hl = 'Constant' }, -- Variable
  [14] = { icon = '󰏿', hl = 'Constant' }, -- Constant
  [15] = { icon = '󰉿', hl = 'String' }, -- String
  [16] = { icon = '󰎠', hl = 'Number' }, -- Number
  [17] = { icon = '󰨙', hl = 'Boolean' }, -- Boolean
  [18] = { icon = '󰅪', hl = 'Type' }, -- Array
  [19] = { icon = '󰅩', hl = 'Type' }, -- Object
  [20] = { icon = '󰌋', hl = 'Identifier' }, -- Key
  [21] = { icon = '󰟢', hl = 'Comment' }, -- Null
  [22] = { icon = '󰕘', hl = 'Type' }, -- EnumMember
  [23] = { icon = '󰙅', hl = 'Type' }, -- Struct
  [24] = { icon = '󱐋', hl = 'Special' }, -- Event
  [25] = { icon = '󰃬', hl = 'Operator' }, -- Operator
  [26] = { icon = '󰊄', hl = 'Type' }, -- TypeParameter
}

local function get_icon(kind)
  local entry = symbol_icons[kind]
  if entry then
    return entry.icon, entry.hl
  end
  return '', 'Normal'
end

local function lsp_symbols_to_tree(symbols, old_nodes)
  local old_map = {}
  if old_nodes then
    for _, n in ipairs(old_nodes) do
      old_map[n.name .. ':' .. (n.kind or 0)] = n
    end
  end

  local nodes = {}
  for _, sym in ipairs(symbols) do
    local key = sym.name .. ':' .. (sym.kind or 0)
    local old = old_map[key]
    local expanded = old and old.expanded or false
    local old_children = old and old.children or nil

    local node = {
      name = sym.name,
      type = (sym.children and #sym.children > 0) and 'directory' or 'file',
      kind = sym.kind,
      range = sym.range or (sym.location and sym.location.range),
      selection_range = sym.selectionRange,
      detail = sym.detail,
      expanded = expanded,
    }
    if sym.children and #sym.children > 0 then
      node.children = lsp_symbols_to_tree(sym.children, old_children)
    end
    nodes[#nodes + 1] = node
  end
  return nodes
end

function M.render()
  local symbols_state = state.symbols
  local nodes = symbols_state.nodes or {}

  if #nodes == 0 then
    local lines = { '  No symbols' }
    symbols_state.display_items = {}
    render.flush(lines, {}, {})
    return
  end

  local lines, items, highlights, virt_texts = render.render_tree(nodes, {
    get_dir_icon = function(node)
      local icon, _ = get_icon(node.kind)
      local arrow = node.expanded and '' or ''
      return arrow .. ' ' .. icon
    end,
    get_file_icon = function(node)
      local icon, hl = get_icon(node.kind)
      return icon, hl
    end,
    file_suffix = function(node)
      if node.detail and node.detail ~= '' then
        return node.detail, 'Comment'
      end
      return nil, nil
    end,
    dir_suffix = function(node)
      if node.detail and node.detail ~= '' then
        return node.detail, 'Comment'
      end
      return nil, nil
    end,
    item_data = function(node)
      return { kind = node.kind, range = node.range, selection_range = node.selection_range }
    end,
  })

  if #lines == 0 then
    lines = { '  No symbols' }
    items = {}
    highlights = {}
    virt_texts = {}
  end

  -- Override folder name highlight with kind-based highlight
  for _, h in ipairs(highlights) do
    if h.hl == 'TreeSidebarFolderName' or h.hl == 'TreeSidebarFolderIcon' then
      local item = items[h.line + 1]
      if item and item.kind then
        local _, hl = get_icon(item.kind)
        if h.hl == 'TreeSidebarFolderIcon' then
          h.hl = hl
        end
      end
    end
  end

  for _, vt in ipairs(virt_texts) do
    vt.pos = 'eol'
  end

  symbols_state.display_items = items
  render.flush(lines, highlights, virt_texts)
end

function M.request_symbols(opts)
  opts = opts or {}
  local wins = vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
  local target_buf = nil
  local target_win = nil
  for _, win in ipairs(wins) do
    if win ~= state.win then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].buftype == '' and vim.bo[buf].buflisted then
        target_buf = buf
        target_win = win
        break
      end
    end
  end
  if not target_buf then
    state.symbols.nodes = {}
    state.symbols.target_buf = nil
    M.render()
    return
  end

  local clients = vim.lsp.get_clients({ bufnr = target_buf })
  local has_symbol_provider = false
  for _, client in ipairs(clients) do
    if client.server_capabilities.documentSymbolProvider then
      has_symbol_provider = true
      break
    end
  end

  if not has_symbol_provider then
    state.symbols.nodes = {}
    state.symbols.target_buf = nil
    M.render()
    return
  end

  local cursor_line = nil
  if opts.locate and target_win then
    cursor_line = vim.api.nvim_win_get_cursor(target_win)[1] - 1
  end

  state.symbols.target_buf = target_buf
  local params = { textDocument = vim.lsp.util.make_text_document_params(target_buf) }
  vim.lsp.buf_request(target_buf, 'textDocument/documentSymbol', params, function(err, result)
    if err or not result then
      state.symbols.nodes = {}
      vim.schedule(function()
        if state.active_tab_idx == 4 then
          M.render()
        end
      end)
      return
    end
    state.symbols.nodes = lsp_symbols_to_tree(result, state.symbols.nodes)
    vim.schedule(function()
      if state.active_tab_idx ~= 4 then
        return
      end
      M.render()
      if cursor_line and state:is_open() then
        M.locate_by_line(cursor_line)
      end
    end)
  end)
end

function M.locate_by_line(cursor_line)
  local items = state.symbols.display_items
  if not items or #items == 0 then
    return
  end
  local best_line = nil
  local best_size = math.huge
  for i, item in ipairs(items) do
    local range = item.range
    if range then
      local start_line = range.start.line
      local end_line = range['end'].line
      if cursor_line >= start_line and cursor_line <= end_line then
        local size = end_line - start_line
        if size < best_size then
          best_size = size
          best_line = i
        end
      end
    end
  end
  if best_line then
    pcall(vim.api.nvim_win_set_cursor, state.win, { best_line, 0 })
  end
end

function M.open_symbol()
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.symbols.display_items[line]
  if not item then
    return
  end

  local range = item.selection_range or item.range
  if not range then
    return
  end

  local target_buf = state.symbols.target_buf
  local target_win = nil
  if target_buf then
    local wins = vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_get_buf(win) == target_buf then
        target_win = win
        break
      end
    end
  end

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd('wincmd p')
  end

  local row = range.start.line
  local col = range.start.character
  pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
end

function M.toggle_node()
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.symbols.display_items[line]
  if not item or not item.node then
    return
  end
  if item.node.type == 'directory' then
    item.node.expanded = not item.node.expanded
    M.render()
    pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
  else
    M.open_symbol()
  end
end

function M.close_node()
  render.close_node({
    get_items = function() return state.symbols.display_items end,
    render_fn = M.render,
    is_closeable = function(item)
      return item.node and item.node.type == 'directory' and item.node.expanded
    end,
    close = function(item)
      item.node.expanded = false
    end,
  })
end

function M.keymaps()
  return {
    { 'l', M.toggle_node, desc = 'Expand node' },
    { 'h', M.close_node, desc = 'Collapse node' },
    { '<cr>', M.open_symbol, desc = 'Go to symbol' },
    { 'r', M.request_symbols, desc = 'Refresh' },
  }
end

return M
