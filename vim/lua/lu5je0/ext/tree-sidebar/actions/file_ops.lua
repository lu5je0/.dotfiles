local state = require('lu5je0.ext.tree-sidebar.state')
local clipboard = require('lu5je0.core.clipboard')

local M = {}

M._clipboard = nil

local _mark_ns = vim.api.nvim_create_namespace('tree_sidebar_clipboard')

function M.apply_clipboard_mark()
  if not state:is_buf_valid() then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.buf, _mark_ns, 0, -1)
  if not M._clipboard then
    return
  end
  local items = state.files.display_items or {}
  for line, item in ipairs(items) do
    if item.node and item.node.abs_path == M._clipboard.path then
      vim.api.nvim_buf_set_extmark(state.buf, _mark_ns, line - 1, 0, {
        line_hl_group = M._clipboard.action == 'move' and 'TreeSidebarCut' or 'TreeSidebarCopy',
      })
      break
    end
  end
end

local function get_current_node()
  if not state:is_open() then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.files.display_items[line]
  if not item or not item.node then
    return nil
  end
  return item.node
end

local function get_parent_dir()
  local node = get_current_node()
  if not node then
    return vim.fn.getcwd()
  end
  if node.type == 'directory' then
    return node.abs_path
  end
  return vim.fs.dirname(node.abs_path)
end

local function refresh()
  local files = require('lu5je0.ext.tree-sidebar.sources.files')
  files.refresh()
end

function M.create_file()
  local dir = get_parent_dir()
  vim.ui.input({ prompt = 'Create file: ', default = dir .. '/' }, function(path)
    if not path or path == '' or path == dir .. '/' then
      return
    end
    local parent = vim.fs.dirname(path)
    vim.fn.mkdir(parent, 'p')
    local fd = vim.uv.fs_open(path, 'w', 420)
    if fd then
      vim.uv.fs_close(fd)
    end
    refresh()
  end)
end

function M.create_dir()
  local dir = get_parent_dir()
  vim.ui.input({ prompt = 'Create directory: ', default = dir .. '/' }, function(path)
    if not path or path == '' or path == dir .. '/' then
      return
    end
    vim.fn.mkdir(path, 'p')
    refresh()
  end)
end

function M.rename()
  local node = get_current_node()
  if not node then
    return
  end
  vim.ui.input({ prompt = 'Rename: ', default = node.abs_path }, function(new_path)
    if not new_path or new_path == '' or new_path == node.abs_path then
      return
    end
    local parent = vim.fs.dirname(new_path)
    vim.fn.mkdir(parent, 'p')
    vim.uv.fs_rename(node.abs_path, new_path)

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf) == node.abs_path then
        vim.api.nvim_buf_set_name(buf, new_path)
        vim.api.nvim_buf_call(buf, function()
          vim.cmd('silent! write!')
        end)
        break
      end
    end
    refresh()
  end)
end

function M.delete()
  local node = get_current_node()
  if not node then
    return
  end
  local choice = vim.fn.confirm('Delete ' .. node.name .. '?', '&Yes\n&No', 2)
  if choice ~= 1 then
    return
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_path = vim.api.nvim_buf_get_name(buf)
    if buf_path == node.abs_path or vim.startswith(buf_path, node.abs_path .. '/') then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  vim.fn.delete(node.abs_path, 'rf')
  refresh()
end

function M.cut()
  local node = get_current_node()
  if not node then
    return
  end
  M._clipboard = { action = 'move', path = node.abs_path }
  M.apply_clipboard_mark()
  print('Cut: ' .. node.name)
end

function M.copy()
  local node = get_current_node()
  if not node then
    return
  end
  M._clipboard = { action = 'copy', path = node.abs_path }
  M.apply_clipboard_mark()
  print('Copy: ' .. node.name)
end

function M.paste()
  if not M._clipboard then
    print('Nothing in clipboard')
    return
  end

  local dest_dir = get_parent_dir()
  local src = M._clipboard.path
  local name = vim.fs.basename(src)
  local dest = dest_dir .. '/' .. name

  if M._clipboard.action == 'move' then
    vim.uv.fs_rename(src, dest)
  elseif M._clipboard.action == 'copy' then
    vim.fn.system({ 'cp', '-r', src, dest })
  end
  M._clipboard = nil
  refresh()
end

function M.copy_name()
  local node = get_current_node()
  if not node then
    return
  end
  clipboard.set(node.name)
  print('Copied: ' .. node.name)
end

function M.copy_absolute_path()
  local node = get_current_node()
  if not node then
    return
  end
  clipboard.set(node.abs_path)
  print('Copied: ' .. node.abs_path)
end

function M.copy_relative_path()
  local node = get_current_node()
  if not node then
    return
  end
  local cwd = vim.fn.getcwd()
  local rel = node.abs_path:sub(#cwd + 2)
  clipboard.set(rel)
  print('Copied: ' .. rel)
end

function M.system_open()
  local node = get_current_node()
  if not node then
    return
  end
  local cmd
  if vim.fn.has('mac') == 1 then
    cmd = { 'open', node.abs_path }
  elseif vim.fn.has('wsl') == 1 then
    cmd = { 'wslview', node.abs_path }
  else
    cmd = { 'xdg-open', node.abs_path }
  end
  vim.system(cmd, { detach = true })
end

return M
