local state = require('lu5je0.ext.sidebar.state')
local clipboard = require('lu5je0.core.clipboard')
local tree = require('lu5je0.ext.sidebar.sources.files.tree')

local M = {}

local _mark_ns = vim.api.nvim_create_namespace('sidebar_clipboard')

function M.apply_clipboard_mark()
  if not state:is_buf_valid() then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.buf, _mark_ns, 0, -1)
  local cb = state.files._clipboard
  if not cb then
    vim.cmd('redrawstatus')
    return
  end
  vim.cmd('redrawstatus')
  local paths = {}
  for _, p in ipairs(cb.paths or {}) do
    paths[p] = true
  end
  local hl = cb.action == 'move' and 'SidebarCut' or 'SidebarCopy'
  local items = state.files.display_items or {}
  for line, item in ipairs(items) do
    if item.node and paths[item.node.abs_path] then
      vim.api.nvim_buf_set_extmark(state.buf, _mark_ns, line - 1, 0, {
        line_hl_group = hl,
      })
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

local function get_visual_nodes()
  if not state:is_open() then return {} end
  local s = vim.fn.getpos('v')[2]
  local e = vim.fn.getpos('.')[2]
  if s > e then s, e = e, s end
  -- exit visual back to normal so the cursor lands on a single line afterwards
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  local items = state.files.display_items or {}
  local nodes, seen = {}, {}
  for line = s, e do
    local item = items[line]
    if item and item.node and item.type ~= 'root' and item.type ~= 'filter' then
      if not seen[item.node.abs_path] then
        seen[item.node.abs_path] = true
        nodes[#nodes + 1] = item.node
      end
    end
  end
  return nodes
end

local function get_parent_dir()
  local node = get_current_node()
  if not node then
    return vim.fn.getcwd()
  end
  if node.type == 'directory' and node.expanded then
    return node.abs_path
  end
  return vim.fs.dirname(node.abs_path)
end

local function refresh()
  local files = require('lu5je0.ext.sidebar.sources.files')
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
  if not node then return end
  local dir = vim.fs.dirname(node.abs_path)

  vim.ui.input({ prompt = 'Rename: ', default = node.name, completion = 'file' }, function(new_name)
    if not new_name or new_name == '' or new_name == node.name then return end
    local new_path = dir .. '/' .. new_name
    local is_case_rename = new_path:lower() == node.abs_path:lower()
    if not is_case_rename and vim.uv.fs_stat(new_path) then
      vim.notify('Already exists: ' .. new_path, vim.log.levels.WARN)
      return
    end
    local new_parent = vim.fs.dirname(new_path)
    if not vim.uv.fs_stat(new_parent) then
      vim.fn.mkdir(new_parent, 'p')
    end
    vim.uv.fs_rename(node.abs_path, new_path)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local buf_path = vim.api.nvim_buf_get_name(buf)
      if buf_path == node.abs_path or vim.startswith(buf_path, node.abs_path .. '/') then
        local new_buf_path = new_path .. buf_path:sub(#node.abs_path + 1)
        vim.api.nvim_buf_set_name(buf, new_buf_path)
      end
    end
    refresh()
  end)
end

local function has_trash()
  return vim.fn.executable('q-trash') == 1
end

local function trash(abs_path)
  local result = vim.system({ 'q-trash', 'rm', '-rf', abs_path }):wait()
  return result.code == 0
end

local function close_bufs_under(abs_path)
  local bufs_to_delete = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_path = vim.api.nvim_buf_get_name(buf)
    if buf_path == abs_path or vim.startswith(buf_path, abs_path .. '/') then
      bufs_to_delete[buf] = true
    end
  end

  if not next(bufs_to_delete) then
    return
  end

  local affected = {}
  local has_safe = false
  local tabpage = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if win ~= state.win then
      local wc = vim.api.nvim_win_get_config(win)
      if wc.relative == '' then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == '' or vim.bo[buf].buflisted then
          if bufs_to_delete[buf] then
            affected[#affected + 1] = win
          else
            has_safe = true
          end
        end
      end
    end
  end

  if has_safe then
    -- other usable windows exist, just close the affected ones
    for _, win in ipairs(affected) do
      vim.api.nvim_win_close(win, true)
    end
  elseif #affected > 0 then
    -- all usable windows show the deleted file; keep one with an empty buffer to avoid sidebar becoming the sole window
    vim.api.nvim_win_set_buf(affected[1], vim.api.nvim_create_buf(true, false))
    for i = 2, #affected do
      vim.api.nvim_win_close(affected[i], true)
    end
  end

  for buf, _ in pairs(bufs_to_delete) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end

local function collect_delete_fallbacks(target_node)
  if not state:is_open() then return {} end
  local items = state.files.display_items or {}
  local cursor_line
  for i, item in ipairs(items) do
    if item.node and item.node.abs_path == target_node.abs_path then
      cursor_line = i
      break
    end
  end
  if not cursor_line then return {} end
  local fallbacks = {}
  for i = cursor_line + 1, #items do
    local it = items[i]
    if it.node and it.type ~= 'root' and it.type ~= 'filter' then
      fallbacks[#fallbacks + 1] = it.node.abs_path
      break
    end
  end
  for i = cursor_line - 1, 1, -1 do
    local it = items[i]
    if it.node and it.type ~= 'root' and it.type ~= 'filter' then
      fallbacks[#fallbacks + 1] = it.node.abs_path
      break
    end
  end
  return fallbacks
end

local function refresh_after_delete(abs_path, fallbacks)
  local files = require('lu5je0.ext.sidebar.sources.files')
  files.refresh_after_delete(abs_path, fallbacks)
end

function M.delete()
  local node = get_current_node()
  if not node then return end

  local fallbacks = collect_delete_fallbacks(node)

  if has_trash() then
    local choice = vim.fn.confirm('Trash ' .. node.name .. '?', '&Yes\n&No', 2)
    if choice ~= 1 then return end
    if trash(node.abs_path) then
      close_bufs_under(node.abs_path)
      refresh_after_delete(node.abs_path, fallbacks)
    else
      vim.notify('Trash failed', vim.log.levels.ERROR)
    end
  else
    local choice = vim.fn.confirm('Delete ' .. node.name .. '? (permanent)', '&Yes\n&No', 2)
    if choice ~= 1 then return end
    close_bufs_under(node.abs_path)
    vim.fn.delete(node.abs_path, 'rf')
    refresh_after_delete(node.abs_path, fallbacks)
  end
end

function M.cut()
  local node = get_current_node()
  if not node then
    return
  end
  state.files._clipboard = { action = 'move', paths = { node.abs_path } }
  M.apply_clipboard_mark()
  print('Cut: ' .. node.name)
end

function M.copy()
  local node = get_current_node()
  if not node then
    return
  end
  state.files._clipboard = { action = 'copy', paths = { node.abs_path } }
  M.apply_clipboard_mark()
  print('Copy: ' .. node.name)
end

function M.cut_visual()
  local nodes = get_visual_nodes()
  if #nodes == 0 then return end
  local paths = {}
  for _, n in ipairs(nodes) do paths[#paths + 1] = n.abs_path end
  state.files._clipboard = { action = 'move', paths = paths }
  M.apply_clipboard_mark()
  print(string.format('Cut: %d item%s', #paths, #paths == 1 and '' or 's'))
end

function M.copy_visual()
  local nodes = get_visual_nodes()
  if #nodes == 0 then return end
  local paths = {}
  for _, n in ipairs(nodes) do paths[#paths + 1] = n.abs_path end
  state.files._clipboard = { action = 'copy', paths = paths }
  M.apply_clipboard_mark()
  print(string.format('Copy: %d item%s', #paths, #paths == 1 and '' or 's'))
end

function M.paste()
  local cb = state.files._clipboard
  if not cb or not cb.paths or #cb.paths == 0 then
    print('Nothing in clipboard')
    return
  end

  local node = get_current_node()
  local dest_dir
  if not node then
    dest_dir = vim.fn.getcwd()
  elseif node.type == 'directory' then
    dest_dir = node.abs_path
  else
    dest_dir = vim.fs.dirname(node.abs_path)
  end

  local function do_one(src, final_dest)
    if cb.action == 'move' then
      vim.uv.fs_rename(src, final_dest)
    elseif cb.action == 'copy' then
      vim.fn.system({ 'cp', '-r', src, final_dest })
    end
  end

  local function unique_dest(dest)
    if not vim.uv.fs_stat(dest) then return dest end
    local dir = vim.fs.dirname(dest)
    local base = vim.fs.basename(dest)
    local stem, ext = base:match('^(.-)(%.[^.]+)$')
    if not stem then stem, ext = base, '' end
    for i = 1, 999 do
      local suffix = i == 1 and '-copy' or ('-copy-' .. i)
      local candidate = dir .. '/' .. stem .. suffix .. ext
      if not vim.uv.fs_stat(candidate) then return candidate end
    end
    return nil
  end

  local function finish()
    state.files._clipboard = nil
    refresh()
  end

  -- Single-item paste keeps the legacy rename-on-conflict prompt.
  if #cb.paths == 1 then
    local src = cb.paths[1]
    local name = vim.fs.basename(src)
    local dest = dest_dir .. '/' .. name
    if vim.uv.fs_stat(dest) then
      vim.ui.input({ prompt = 'Rename to: ', default = dest }, function(new_dest)
        if not new_dest or new_dest == '' then return end
        if vim.uv.fs_stat(new_dest) then
          vim.notify('Target already exists: ' .. new_dest, vim.log.levels.WARN)
          return
        end
        do_one(src, new_dest)
        finish()
      end)
      return
    end
    do_one(src, dest)
    finish()
    return
  end

  -- Multi-item paste auto-renames conflicts to keep the flow non-interactive.
  local count = 0
  for _, src in ipairs(cb.paths) do
    local name = vim.fs.basename(src)
    local dest = dest_dir .. '/' .. name
    local final_dest = vim.uv.fs_stat(dest) and unique_dest(dest) or dest
    if final_dest then
      do_one(src, final_dest)
      count = count + 1
    end
  end
  print(string.format('Pasted: %d item%s', count, count == 1 and '' or 's'))
  finish()
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
  local rel = tree.rel_to_cwd(node.abs_path)
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
