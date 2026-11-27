-- View layer: all buffer/window writes for the sidebar.
-- Pure helpers; never mutates source state. The render engine in
-- render.lua now only produces lines/items/highlights/virt_texts; this
-- module flushes them and provides cursor-aware open/close/restore glue.
local state = require('lu5je0.ext.sidebar.state')

local M = {}

local ns_id = vim.api.nvim_create_namespace('sidebar')

function M.ns_id()
  return ns_id
end

function M.set_lines(lines, first, last)
  if not state:is_buf_valid() then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, first or 0, last or -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

function M.clear_highlights(first, last)
  if not state:is_buf_valid() then return end
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, first or 0, last or -1)
end

function M.add_highlight(line, hl_group, col_start, col_end)
  if not state:is_buf_valid() then return end
  vim.api.nvim_buf_add_highlight(state.buf, ns_id, hl_group, line, col_start, col_end)
end

function M.flush(lines, highlights, virt_texts, first, last)
  first = first or 0
  M.clear_highlights(first, last)
  M.set_lines(lines, first, last)
  for _, h in ipairs(highlights) do
    if h.line_hl_group then
      vim.api.nvim_buf_set_extmark(state.buf, ns_id, first + h.line, 0, { line_hl_group = h.line_hl_group })
    else
      M.add_highlight(first + h.line, h.hl, h.col_start, h.col_end)
    end
  end
  for _, vt in ipairs(virt_texts or {}) do
    vim.api.nvim_buf_set_extmark(state.buf, ns_id, first + vt.line, 0, {
      virt_text = vt.virt_text,
      virt_text_pos = vt.pos or 'right_align',
      hl_mode = 'combine',
    })
  end
end

local function cursor_line()
  return vim.api.nvim_win_get_cursor(state.win)[1]
end

function M.current_item(items)
  if not state:is_open() then return end
  local line = cursor_line()
  return items[line], line
end

local function set_cursor(line, col)
  pcall(vim.api.nvim_win_set_cursor, state.win, { line, col or 0 })
end

function M.open_node(opts)
  local item, line = M.current_item(opts.get_items())
  if not item then return end

  if opts.is_expandable(item) then
    local keep_cursor = opts.keep_cursor and opts.keep_cursor(item)
    if not opts.is_expanded(item) then
      opts.expand(item, line)
      opts.render_fn()
      if not opts.fold_only then set_cursor(keep_cursor and line or line + 1) end
    elseif not opts.fold_only and not keep_cursor and opts.on_already_expanded then
      opts.on_already_expanded(item, line)
    end
    return
  end

  if not opts.fold_only and item.type == 'file' and opts.on_file then
    opts.on_file(item, line)
  end
end

function M.close_node(opts)
  local item = M.current_item(opts.get_items())
  while item and not opts.is_closeable(item) do item = item.parent end
  if not item then return end
  local row = item.line_idx + 1
  opts.close(item)
  opts.render_fn()
  set_cursor(row)
end

function M.item_has_path(item, path)
  if item.node and item.node.abs_path == path then return true end
  if item.dir_chain then
    for _, dir in ipairs(item.dir_chain) do
      if dir.abs_path == path then return true end
    end
  end
  return false
end

function M.restore_cursor(old_items, new_items, cursor)
  local line = cursor and cursor[1] or cursor_line()
  local old_node = old_items[line] and old_items[line].node
  if not old_node then
    set_cursor(1)
    return
  end

  local function contains(node, target)
    if node == target then return true end
    if node.children then
      for _, child in ipairs(node.children) do
        if contains(child, target) then return true end
      end
    end
    return false
  end

  for i, item in ipairs(new_items) do
    if item.node == old_node or (item.dir_chain and vim.list_contains(item.dir_chain, old_node)) then
      set_cursor(i, cursor and cursor[2])
      return
    end
  end

  local best_line = 1
  for i, item in ipairs(new_items) do
    local root = item.dir_chain and item.dir_chain[1] or item.node
    if root and contains(root, old_node) then
      best_line = i
    end
  end
  set_cursor(best_line)
end

return M
