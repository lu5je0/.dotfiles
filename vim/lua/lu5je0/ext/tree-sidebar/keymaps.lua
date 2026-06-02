local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')

local M = {}

M._current_tab_keymaps = {}

local function buf_set(mode, lhs, rhs, opts)
  opts = opts or {}
  opts.buffer = state.buf
  opts.noremap = true
  opts.silent = true
  opts.nowait = true
  vim.keymap.set(mode, lhs, rhs, opts)
end

local function buf_del(mode, lhs)
  pcall(vim.keymap.del, mode, lhs, { buffer = state.buf })
end

function M.apply_shared()
  if not state:is_buf_valid() then
    return
  end

  local tabs = require('lu5je0.ext.tree-sidebar.tabs')
  local window = require('lu5je0.ext.tree-sidebar.window')

  buf_set('n', '<right>', tabs.next_tab)
  buf_set('n', '<left>', tabs.prev_tab)
  buf_set('n', '1', function() tabs.switch_to(1) end)
  buf_set('n', '2', function() tabs.switch_to(2) end)
  buf_set('n', '3', function() tabs.switch_to(3) end)
  buf_set('n', '4', function() tabs.switch_to(4) end)
  buf_set('n', 'q', window.close)
  buf_set('n', 'Z', window.toggle_width)
  buf_set('n', '<leader>tn', function() end)

  buf_set('n', 'zM', function()
    local source = tabs.get_active_source()
    if source and source.collapse_all then
      source.collapse_all()
    end
  end)

  local preview_mod = require('lu5je0.ext.tree-sidebar.actions.preview')
  local file_ops = require('lu5je0.ext.tree-sidebar.actions.file_ops')
  buf_set('n', '<esc>', function()
    if preview_mod.is_active() then
      preview_mod.stop()
    end
    if file_ops._clipboard then
      file_ops._clipboard = nil
      file_ops.apply_clipboard_mark()
    end
  end)

  local help = require('lu5je0.ext.git.common.help')
  local shared_keymaps = {
    { '<left>/<right>', 'Switch tab' },
    { '1/2/3/4', 'Jump to tab' },
    { 'q', 'Close sidebar' },
    { 'Z', 'Toggle width' },
    { 'zM', 'Collapse all' },
    { '<esc>', 'Close preview / Clear clipboard' },
    { '?', 'Show help' },
  }
  buf_set('n', '?', function()
    local tab = config.tabs[state.active_tab_idx]
    local ok, source = pcall(require, 'lu5je0.ext.tree-sidebar.sources.' .. (tab and tab.id or ''))
    local lines = { 'Shared', '' }
    for _, km in ipairs(shared_keymaps) do
      lines[#lines + 1] = string.format('  %-14s  %s', km[1], km[2])
    end
    if ok and source.keymaps then
      lines[#lines + 1] = ''
      lines[#lines + 1] = tab.label
      lines[#lines + 1] = ''
      local seen = {}
      for _, km in ipairs(source.keymaps()) do
        local desc = km.desc or ''
        if not seen[desc] then
          seen[desc] = true
          lines[#lines + 1] = string.format('  %-14s  %s', km[1], desc)
        end
      end
    end
    help.show_help('Help', lines)
  end)

  buf_set('n', 'j', function()
    local keys = require('lu5je0.core.keys')
    keys.feedkey('j', 'n')
  end)
  buf_set('n', 'k', function()
    local keys = require('lu5je0.core.keys')
    keys.feedkey('k', 'n')
  end)
end

function M.apply_for_tab(idx)
  for _, km in ipairs(M._current_tab_keymaps) do
    buf_del(km.mode, km.lhs)
  end
  M._current_tab_keymaps = {}

  local tab = config.tabs[idx]
  if not tab then
    return
  end

  local ok, source = pcall(require, 'lu5je0.ext.tree-sidebar.sources.' .. tab.id)
  if not ok or not source.keymaps then
    return
  end

  for _, km in ipairs(source.keymaps()) do
    buf_set(km.mode or 'n', km[1], km[2], { desc = km.desc })
    M._current_tab_keymaps[#M._current_tab_keymaps + 1] = { mode = km.mode or 'n', lhs = km[1] }
  end
end

return M
