-- Buffers source: list of valid loaded buffers.
local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local source_base = require('lu5je0.ext.tree-sidebar.source_base')

local M = {}

local spec = { id = 'buffers', state_key = 'buffers' }
M._spec = spec

local function get_buffer_list()
  local bufs = require('lu5je0.core.buffers').valid_buffers()
  local items, basenames = {}, {}

  for _, buf in ipairs(bufs) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= '' then
      local basename = vim.fs.basename(name)
      basenames[basename] = (basenames[basename] or 0) + 1
      items[#items + 1] = {
        buf = buf, path = name, basename = basename,
        modified = vim.bo[buf].modified,
      }
    else
      local buffer_name_map = require('lu5je0.ext.bufferline').buffer_name_map
      local num = buffer_name_map[buf]
      items[#items + 1] = {
        buf = buf, path = '',
        basename = num and ('Untitled-' .. num) or '[No Name]',
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

function spec.build(_ts, _ctx)
  local list = get_buffer_list()
  local nodes = {}
  for _, item in ipairs(list) do
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

function spec.render_opts(_ts, _ctx)
  return {
    file_suffix = function(node)
      if node.modified then return '●', 'TreeSidebarModified' end
    end,
    item_data = function(node) return { buf = node.buf } end,
  }
end

function spec.decorate(_ts, lines, _items, _hls, _vt, _ctx)
  if #lines == 0 then
    return { '  No buffers' }, {}, {}, {}
  end
end

function M.render()
  source_base.render(spec)
end

function M.open_buffer()
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.buffers.display_items[line]
  if not item or not item.node then return end

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
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.buffers.display_items[line]
  if not item or not item.node then return end

  if vim.bo[item.node.buf].modified then
    local choice = vim.fn.confirm('Buffer is modified. Close anyway?', '&Yes\n&No', 2)
    if choice ~= 1 then return end
  end

  vim.api.nvim_buf_delete(item.node.buf, { force = true })
  M.render()
end

function M.locate_buffer(bufnr)
  for line, item in ipairs(state.buffers.display_items or {}) do
    if item.node and item.node.buf == bufnr then
      vim.api.nvim_win_set_cursor(state.win, { line, 0 })
      return
    end
  end
end

function M.keymaps()
  local preview = require('lu5je0.ext.tree-sidebar.actions.preview')
  return {
    { 'l', M.open_buffer, desc = 'Open buffer' },
    { '<cr>', M.open_buffer, desc = 'Open buffer' },
    { 'D', M.close_buffer, desc = 'Close buffer' },
    { 'r', M.render, desc = 'Refresh' },
    { '<space>', preview.toggle, desc = 'Preview' },
  }
end

function M.setup_auto_refresh(group)
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
