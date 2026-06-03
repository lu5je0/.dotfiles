-- View layer: all buffer/window writes for the sidebar.
-- Pure helpers; never mutates source state. The render engine in
-- render.lua now only produces lines/items/highlights/virt_texts; this
-- module flushes them and provides cursor-aware open/close/restore glue.
local state = require('lu5je0.ext.tree-sidebar.state')

local M = {}

local ns_id = vim.api.nvim_create_namespace('tree_sidebar')

function M.ns_id()
  return ns_id
end

function M.set_lines(lines)
  if not state:is_buf_valid() then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

function M.clear_highlights()
  if not state:is_buf_valid() then return end
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)
end

function M.add_highlight(line, hl_group, col_start, col_end)
  if not state:is_buf_valid() then return end
  vim.api.nvim_buf_add_highlight(state.buf, ns_id, hl_group, line, col_start, col_end)
end

function M.flush(lines, highlights, virt_texts)
  M.set_lines(lines)
  M.clear_highlights()
  for _, h in ipairs(highlights) do
    M.add_highlight(h.line, h.hl, h.col_start, h.col_end)
  end
  for _, vt in ipairs(virt_texts or {}) do
    vim.api.nvim_buf_set_extmark(state.buf, ns_id, vt.line, 0, {
      virt_text = vt.virt_text,
      virt_text_pos = vt.pos or 'right_align',
      hl_mode = 'combine',
    })
  end
end

local function cursor_line()
  return vim.api.nvim_win_get_cursor(state.win)[1]
end

local function set_cursor(line)
  pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
end

function M.open_node(opts)
  if not state:is_open() then return end
  local line = cursor_line()
  local item = opts.get_items()[line]
  if not item then return end

  if opts.is_expandable(item) then
    if not opts.is_expanded(item) then
      opts.expand(item, line)
      opts.render_fn()
      set_cursor(line + 1)
    elseif opts.on_already_expanded then
      opts.on_already_expanded(item, line)
    end
    return
  end

  if item.type == 'file' and opts.on_file then
    opts.on_file(item, line)
  end
end

function M.close_node(opts)
  if not state:is_open() then return end
  local line = cursor_line()
  local items = opts.get_items()
  local item = items[line]
  if not item then return end

  if opts.is_closeable(item) then
    opts.close(item, line)
    opts.render_fn()
    set_cursor(line)
    return
  end

  for i = line - 1, 1, -1 do
    local parent = items[i]
    if parent then
      if opts.is_boundary and opts.is_boundary(parent) then
        set_cursor(i)
        return
      end
      if opts.is_closeable(parent) then
        opts.close(parent, i)
        opts.render_fn()
        set_cursor(i)
        return
      end
    end
  end
end

function M.restore_cursor(old_items, new_items)
  local line = cursor_line()
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
    if item.node == old_node then
      set_cursor(i)
      return
    end
  end

  local best_line = 1
  for i, item in ipairs(new_items) do
    if item.node and contains(item.node, old_node) then
      best_line = i
    end
  end
  set_cursor(best_line)
end

return M
