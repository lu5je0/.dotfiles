local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local render = require('lu5je0.ext.tree-sidebar.render')

local M = {}

local function get_buffer_list()
  local bufs = require('lu5je0.core.buffers').valid_buffers()
  local items = {}
  local basenames = {}

  for _, buf in ipairs(bufs) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= '' then
      local basename = vim.fs.basename(name)
      basenames[basename] = (basenames[basename] or 0) + 1
      items[#items + 1] = {
        buf = buf,
        path = name,
        basename = basename,
        modified = vim.bo[buf].modified,
      }
    else
      local buffer_name_map = require('lu5je0.ext.bufferline').buffer_name_map
      local num = buffer_name_map[buf]
      local display = num and ('Untitled-' .. num) or '[No Name]'
      items[#items + 1] = {
        buf = buf,
        path = '',
        basename = display,
        modified = vim.bo[buf].modified,
      }
    end
  end

  for _, item in ipairs(items) do
    if item.path ~= '' and (basenames[item.basename] or 0) > 1 then
      item.display_name = vim.fn.fnamemodify(item.path, ':~:.')
    else
      item.display_name = item.basename
    end
  end

  return items
end

local function buffers_to_tree_nodes(buffer_list)
  local nodes = {}
  for _, item in ipairs(buffer_list) do
    nodes[#nodes + 1] = {
      name = item.display_name,
      type = 'file',
      abs_path = item.path,
      buf = item.buf,
      modified = item.modified,
    }
  end
  return nodes
end

function M.render()
  local buffer_list = get_buffer_list()
  local nodes = buffers_to_tree_nodes(buffer_list)

  local lines, items, highlights, virt_texts = render.render_tree(nodes, {
    file_suffix = function(node)
      if node.modified then
        return '●', 'TreeSidebarModified'
      end
      return nil, nil
    end,
    item_data = function(node)
      return { buf = node.buf }
    end,
  })

  if #lines == 0 then
    lines = { '  No buffers' }
    items = {}
    highlights = {}
  end

  state.buffers.display_items = items
  render.flush(lines, highlights, virt_texts)
end

function M.open_buffer()
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.buffers.display_items[line]
  if not item or not item.node then
    return
  end

  local win = require('lu5je0.ext.tree-sidebar.window')
  local target = win.get_target_win()
  if target then
    vim.api.nvim_set_current_win(target)
  else
    vim.cmd('belowright vsplit')
  end
  vim.api.nvim_set_current_buf(item.node.buf)
end

function M.close_buffer()
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.buffers.display_items[line]
  if not item or not item.node then
    return
  end

  if vim.bo[item.node.buf].modified then
    local choice = vim.fn.confirm('Buffer is modified. Close anyway?', '&Yes\n&No', 2)
    if choice ~= 1 then
      return
    end
  end

  vim.api.nvim_buf_delete(item.node.buf, { force = true })
  M.render()
end

function M.locate_buffer(bufnr)
  local items = state.buffers.display_items
  if not items then
    return
  end
  for line, item in ipairs(items) do
    if item.node and item.node.buf == bufnr then
      vim.api.nvim_win_set_cursor(state.win, { line, 0 })
      return
    end
  end
end

function M.keymaps()
  local preview_mod = require('lu5je0.ext.tree-sidebar.actions.preview')
  return {
    { 'l', M.open_buffer, desc = 'Open buffer' },
    { '<cr>', M.open_buffer, desc = 'Open buffer' },
    { 'D', M.close_buffer, desc = 'Close buffer' },
    { 'r', M.render, desc = 'Refresh' },
    { '<space>', preview_mod.toggle, desc = 'Preview' },
  }
end

function M.setup_auto_refresh()
  local group = vim.api.nvim_create_augroup('tree-sidebar-buffers', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufAdd', 'BufDelete', 'BufWipeout', 'BufModifiedSet' }, {
    group = group,
    callback = function()
      if state:is_open() and state.active_tab_idx == config.tab_idx('buffers') then
        vim.schedule(M.render)
      end
    end,
  })
end

return M
