local state = require('lu5je0.ext.tree-sidebar.state')
local render = require('lu5je0.ext.tree-sidebar.render')
local config = require('lu5je0.ext.tree-sidebar.config')

local M = {}

local _watchers = {}
local _refresh_timer = nil
local DEBOUNCE_MS = 300

local function debounced_refresh()
  if _refresh_timer then
    _refresh_timer:stop()
  end
  _refresh_timer = vim.uv.new_timer()
  _refresh_timer:start(DEBOUNCE_MS, 0, function()
    _refresh_timer:close()
    _refresh_timer = nil
    vim.schedule(function()
      if state:is_open() and state.active_tab_idx == 1 then
        M.refresh()
      end
    end)
  end)
end

local function stop_all_watchers()
  for _, w in pairs(_watchers) do
    pcall(function() w:stop() end)
    pcall(function() w:close() end)
  end
  _watchers = {}
end

local function collect_expanded_dirs(node, dirs)
  if not node or node.type ~= 'directory' then
    return
  end
  dirs[node.abs_path] = true
  if node.expanded and node.children then
    for _, child in ipairs(node.children) do
      if child.type == 'directory' and child.expanded then
        collect_expanded_dirs(child, dirs)
      end
    end
  end
end

local function sync_watchers()
  if not state.files.root then
    stop_all_watchers()
    return
  end

  local wanted = {}
  collect_expanded_dirs(state.files.root, wanted)

  for path, w in pairs(_watchers) do
    if not wanted[path] then
      pcall(function() w:stop() end)
      pcall(function() w:close() end)
      _watchers[path] = nil
    end
  end

  for path, _ in pairs(wanted) do
    if not _watchers[path] then
      local handle = vim.uv.new_fs_event()
      if handle then
        local ok = pcall(function()
          handle:start(path, {}, function(err)
            if not err then
              debounced_refresh()
            end
          end)
        end)
        if ok then
          _watchers[path] = handle
        else
          pcall(function() handle:close() end)
        end
      end
    end
  end
end

local function scan_dir(path)
  local handle = vim.uv.fs_scandir(path)
  if not handle then
    return {}
  end
  local entries = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    entries[#entries + 1] = {
      name = name,
      abs_path = path .. '/' .. name,
      type = type or 'file',
      children = nil,
      expanded = false,
    }
  end
  table.sort(entries, function(a, b)
    if a.type == 'directory' and b.type ~= 'directory' then
      return true
    end
    if a.type ~= 'directory' and b.type == 'directory' then
      return false
    end
    return a.name < b.name
  end)
  return entries
end

local function is_dotfile(name)
  return name:sub(1, 1) == '.'
end

local function ensure_children(node)
  if node.type == 'directory' and node.children == nil then
    node.children = scan_dir(node.abs_path)
  end
end

local function build_root()
  local cwd = vim.fn.getcwd()
  local root = {
    name = vim.fs.basename(cwd),
    abs_path = cwd,
    type = 'directory',
    children = scan_dir(cwd),
    expanded = true,
  }
  state.files.root = root
  return root
end

local function node_filter(node)
  if state.files.hide_dotfiles and is_dotfile(node.name) then
    return false
  end
  return true
end

local function file_suffix(node)
  local rel_path = node.abs_path:sub(#vim.fn.getcwd() + 2)
  local git_info = state.files.git_status_map[rel_path]
  if git_info then
    return git_info.glyph, git_info.hl
  end
  return nil, nil
end

local function dir_suffix(node)
  local rel_path = node.abs_path:sub(#vim.fn.getcwd() + 2) .. '/'
  local git_status = state.files.git_status_map[rel_path]
  if git_status then
    return git_status.glyph, git_status.hl
  end
  return nil, nil
end

local function prepare_tree(node)
  ensure_children(node)
  if not node.children then
    return
  end
  for _, child in ipairs(node.children) do
    if child.type == 'directory' and child.expanded then
      prepare_tree(child)
    end
  end
end

local DIR_STATUS_PRIORITY = {
  TreeSidebarGitDirty = 1,
  TreeSidebarGitNew = 2,
  TreeSidebarGitStaged = 3,
}

local function build_git_status_map(stdout)
  local map = {}
  if not stdout or stdout == '' then
    return map
  end
  local dir_status = {}
  local entries = vim.split(stdout, '\0', { trimempty = true })
  local i = 1
  while i <= #entries do
    local entry = entries[i]
    if #entry >= 4 then
      local xy = entry:sub(1, 2)
      local path = entry:sub(4)
      local x = xy:sub(1, 1)
      if x == 'R' or x == 'C' then
        i = i + 1
      end
      local glyph, hl = M._git_status_to_glyph(xy)
      map[path] = { xy = xy, glyph = glyph, hl = hl }
      local parts = vim.split(path, '/', { trimempty = true })
      local dir = ''
      for pi = 1, #parts - 1 do
        dir = dir .. (pi > 1 and '/' or '') .. parts[pi]
        local existing = dir_status[dir]
        if not existing or (DIR_STATUS_PRIORITY[hl] or 99) < (DIR_STATUS_PRIORITY[existing.hl] or 99) then
          dir_status[dir] = { xy = xy, glyph = glyph, hl = hl }
        end
      end
    end
    i = i + 1
  end
  for dir, info in pairs(dir_status) do
    map[dir .. '/'] = info
  end
  return map
end

function M.render()
  if not state.files.root then
    build_root()
  end

  local root = state.files.root
  prepare_tree(root)

  local lines = {}
  local items = {}
  local highlights = {}

  -- Root line (skip if at /)
  local cwd = vim.fn.getcwd()
  if cwd ~= '/' then
    local display_path = vim.fn.fnamemodify(cwd, ':~') .. '/..'
    local root_line = display_path
    lines[#lines + 1] = root_line
    items[#items + 1] = { type = 'root', node = root, line_idx = 0 }
    highlights[#highlights + 1] = { line = 0, hl = 'TreeSidebarRootFolder', col_start = 0, col_end = -1 }
  end

  -- Render tree
  local tree_lines, tree_items, tree_highlights, tree_virt_texts = render.render_tree(root.children or {}, {
    filter = node_filter,
    file_suffix = file_suffix,
    dir_suffix = dir_suffix,
    compress_dirs = state.files.compress_dirs or false,
  })

  -- Merge results (offset line indices)
  local offset = #lines
  for _, l in ipairs(tree_lines) do
    lines[#lines + 1] = l
  end
  for _, item in ipairs(tree_items) do
    item.line_idx = item.line_idx + offset
    items[#items + 1] = item
  end
  for _, h in ipairs(tree_highlights) do
    h.line = h.line + offset
    highlights[#highlights + 1] = h
  end
  local virt_texts = {}
  for _, vt in ipairs(tree_virt_texts) do
    vt.line = vt.line + offset
    virt_texts[#virt_texts + 1] = vt
  end

  state.files.display_items = items
  render.flush(lines, highlights, virt_texts)
  sync_watchers()

  local file_ops = require('lu5je0.ext.tree-sidebar.actions.file_ops')
  file_ops.apply_clipboard_mark()
end

local function rescan_node(node)
  if node.type ~= 'directory' then
    return
  end
  local old_children = node.children or {}
  local old_expanded = {}
  for _, child in ipairs(old_children) do
    if child.type == 'directory' and child.expanded then
      old_expanded[child.name] = child
    end
  end

  node.children = scan_dir(node.abs_path)
  for _, child in ipairs(node.children) do
    if child.type == 'directory' then
      local old = old_expanded[child.name]
      if old then
        child.expanded = true
        child.children = old.children
        rescan_node(child)
      end
    end
  end
end

function M.refresh()
  if state.files.root then
    rescan_node(state.files.root)
  else
    build_root()
  end
  M.refresh_git_status(function()
    M.render()
  end)
end

function M.open_node()
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.files.display_items[line]
  if item and item.type == 'root' then
    M.cd_parent()
    return
  end

  render.open_node({
    get_items = function() return state.files.display_items end,
    render_fn = M.render,
    is_expandable = function(it)
      return it.type == 'dir'
    end,
    is_expanded = function(it) return it.node.expanded end,
    expand = function(it)
      ensure_children(it.node)
      it.node.expanded = true
      if state.files.compress_dirs then
        local node = it.node
        while node.children do
          local dirs = {}
          for _, c in ipairs(node.children) do
            if c.type == 'directory' and node_filter(c) then
              dirs[#dirs + 1] = c
            end
          end
          if #dirs == 1 then
            ensure_children(dirs[1])
            dirs[1].expanded = true
            node = dirs[1]
          else
            break
          end
        end
      end
    end,
    on_already_expanded = function()
      vim.cmd('wincmd p')
    end,
    on_file = function(it)
      vim.cmd('wincmd p')
      vim.cmd('edit ' .. vim.fn.fnameescape(it.node.abs_path))
    end,
  })
end

function M.close_node()
  render.close_node({
    get_items = function() return state.files.display_items end,
    render_fn = M.render,
    is_closeable = function(item)
      return item.type == 'dir' and item.node.expanded
    end,
    close = function(item)
      item.node.expanded = false
    end,
    is_boundary = function(item)
      return item.type == 'root'
    end,
  })
end

function M.toggle_dotfiles()
  local old_line = vim.api.nvim_win_get_cursor(state.win)[1]
  local old_item = state.files.display_items[old_line]
  local old_path = old_item and old_item.node and old_item.node.abs_path

  state.files.hide_dotfiles = not state.files.hide_dotfiles
  M.render()

  if old_path then
    for line, item in ipairs(state.files.display_items) do
      if item.node and item.node.abs_path == old_path then
        pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
        return
      end
    end
  end
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  local target = math.min(old_line, line_count)
  pcall(vim.api.nvim_win_set_cursor, state.win, { math.max(1, target), 0 })
end

local function save_cursor_for_cwd()
  if state:is_open() then
    state.files._cursor_cache = state.files._cursor_cache or {}
    state.files._cursor_cache[vim.fn.getcwd()] = vim.api.nvim_win_get_cursor(state.win)
  end
end

local function restore_cursor_for_cwd()
  local cache = state.files._cursor_cache
  if cache and cache[vim.fn.getcwd()] then
    pcall(vim.api.nvim_win_set_cursor, state.win, cache[vim.fn.getcwd()])
  else
    pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
  end
end

function M.cd_to_node()
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.files.display_items[line]
  if not item then
    return
  end

  local path
  if item.type == 'dir' or item.type == 'root' then
    path = item.node.abs_path
  elseif item.type == 'file' then
    path = vim.fs.dirname(item.node.abs_path)
  end

  if path then
    save_cursor_for_cwd()
    state.files._root_cache = state.files._root_cache or {}
    state.files._root_cache[vim.fn.getcwd()] = state.files.root
    vim.cmd('cd ' .. vim.fn.fnameescape(path))
    local cache = state.files._root_cache
    if cache and cache[path] then
      state.files.root = cache[path]
    else
      state.files.root = nil
    end
    M.render()
    pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
  end
end

function M.cd_parent()
  local cwd = vim.fn.getcwd()
  local parent = vim.fs.dirname(cwd)
  if parent and parent ~= cwd then
    save_cursor_for_cwd()
    state.files._root_cache = state.files._root_cache or {}
    state.files._root_cache[cwd] = state.files.root
    vim.cmd('cd ' .. vim.fn.fnameescape(parent))
    local cache = state.files._root_cache
    state.files.root = cache and cache[parent] or nil
    M.render()
    pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
  end
end

function M.cd_home()
  local cwd = vim.fn.getcwd()
  save_cursor_for_cwd()
  state.files._root_cache = state.files._root_cache or {}
  state.files._root_cache[cwd] = state.files.root
  vim.cmd('cd ~')
  local home = vim.fn.expand('~')
  local cache = state.files._root_cache
  state.files.root = cache and cache[home] or nil
  M.render()
  pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
end

function M.refresh_git_status(callback)
  local tab_files = state.files
  vim.system({ 'git', 'status', '--porcelain=v1', '-z' }, { text = true }, function(result)
    vim.schedule(function()
      tab_files.git_status_map = build_git_status_map(result.code == 0 and result.stdout or '')
      if callback then
        callback()
      end
    end)
  end)
end

function M.update_git_status_from_stdout(tab_files, stdout)
  tab_files.git_status_map = build_git_status_map(stdout or '')
end

function M._git_status_to_glyph(xy)
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  if xy == '??' then
    return config.git_glyphs.untracked, 'TreeSidebarGitNew'
  elseif x == 'D' or y == 'D' then
    return config.git_glyphs.deleted, 'TreeSidebarGitDirty'
  elseif x == 'R' then
    return config.git_glyphs.renamed, 'TreeSidebarGitDirty'
  elseif x == 'A' then
    return config.git_glyphs.staged, 'TreeSidebarGitStaged'
  elseif x ~= ' ' and x ~= '?' then
    return config.git_glyphs.staged, 'TreeSidebarGitStaged'
  elseif y == 'M' then
    return config.git_glyphs.unstaged, 'TreeSidebarGitDirty'
  end
  return config.git_glyphs.unstaged, 'TreeSidebarGitDirty'
end

local function format_size(size)
  if size < 1024 then
    return size .. ' B'
  elseif size < 1024 * 1024 then
    return string.format('%.1f KB', size / 1024)
  elseif size < 1024 * 1024 * 1024 then
    return string.format('%.1f MB', size / (1024 * 1024))
  else
    return string.format('%.1f GB', size / (1024 * 1024 * 1024))
  end
end

function M.show_file_info()
  if not state:is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.files.display_items[line]
  if not item or not item.node then
    return
  end

  local node = item.node
  local stat = vim.uv.fs_stat(node.abs_path)
  if not stat then
    vim.notify('Cannot stat: ' .. node.abs_path, vim.log.levels.WARN)
    return
  end

  local file_type = stat.type or 'unknown'
  local permissions = string.format('%o', stat.mode % 4096)
  local lines = {
    '  Name:         ' .. node.name,
    '  Path:         ' .. node.abs_path,
    '  Type:         ' .. file_type,
    '  Size:         ' .. format_size(stat.size),
    '  Permissions:  ' .. permissions,
    '  Created:      ' .. os.date('%Y-%m-%d %H:%M:%S', stat.birthtime.sec),
    '  Modified:     ' .. os.date('%Y-%m-%d %H:%M:%S', stat.mtime.sec),
    '  Accessed:     ' .. os.date('%Y-%m-%d %H:%M:%S', stat.atime.sec),
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win_width = 0
  for _, l in ipairs(lines) do
    win_width = math.max(win_width, vim.fn.strdisplaywidth(l))
  end
  win_width = win_width + 2
  local win_height = #lines

  local cursor_row = vim.fn.screenpos(state.win, line, 1).row
  local anchor, popup_row
  if cursor_row - 1 - win_height - 2 >= 0 then
    anchor = 'SW'
    popup_row = cursor_row - 1
  else
    anchor = 'NW'
    popup_row = cursor_row
  end

  local sidebar_col = vim.api.nvim_win_get_position(state.win)[2]
  local winid = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    anchor = anchor,
    row = popup_row,
    col = sidebar_col,
    width = win_width,
    height = win_height,
    style = 'minimal',
    border = 'rounded',
    title = ' File Info ',
    title_pos = 'center',
    focusable = false,
    zindex = 100,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave', 'InsertEnter' }, {
    buffer = state.buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
    end,
  })
end

function M.toggle_compress_dirs()
  state.files.compress_dirs = not state.files.compress_dirs
  vim.notify('Group empty: ' .. (state.files.compress_dirs and 'on' or 'off'), vim.log.levels.INFO)
  M.render()
end

function M.keymaps()
  local nav = require('lu5je0.ext.tree-sidebar.actions.navigation')
  local file_ops = require('lu5je0.ext.tree-sidebar.actions.file_ops')
  local preview_mod = require('lu5je0.ext.tree-sidebar.actions.preview')

  return {
    { 'l', M.open_node, desc = 'Open node' },
    { '<cr>', M.open_node, desc = 'Open node' },
    { 'h', M.close_node, desc = 'Close node' },
    { 'u', M.cd_parent, desc = 'Navigate up' },
    { 'cd', M.cd_to_node, desc = 'CD to node' },
    { 'H', M.cd_home, desc = 'CD home' },
    { '<c-o>', nav.back, desc = 'Back' },
    { '<c-i>', nav.forward, desc = 'Forward' },
    { '.', M.toggle_dotfiles, desc = 'Toggle dotfiles' },
    { 'zc', M.toggle_compress_dirs, desc = 'Toggle group empty' },
    { 'r', M.refresh, desc = 'Refresh' },
    { 'ma', file_ops.create_file, desc = 'Create file' },
    { 'mk', file_ops.create_dir, desc = 'Create directory' },
    { 'mv', file_ops.rename, desc = 'Rename' },
    { 'D', file_ops.delete, desc = 'Delete' },
    { 'dd', file_ops.cut, desc = 'Cut' },
    { 'yy', file_ops.copy, desc = 'Copy' },
    { 'p', file_ops.paste, desc = 'Paste' },
    { 'yn', file_ops.copy_name, desc = 'Copy name' },
    { 'yp', file_ops.copy_absolute_path, desc = 'Copy absolute path' },
    { 'yP', file_ops.copy_relative_path, desc = 'Copy relative path' },
    { 'K', M.show_file_info, desc = 'File info' },
    { '<space>', preview_mod.toggle, desc = 'Preview' },
  }
end

function M.find_file(filepath)
  if not filepath or filepath == '' then
    return
  end

  local cwd = vim.fn.getcwd()
  local dir = vim.fs.dirname(filepath)

  if not vim.startswith(dir, cwd) then
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))
    state.files.root = nil
  end

  if state.files.hide_dotfiles then
    local rel = filepath:sub(#cwd + 2)
    local parts = vim.split(rel, '/', { trimempty = true })
    for _, p in ipairs(parts) do
      if is_dotfile(p) then
        state.files.hide_dotfiles = false
        break
      end
    end
  end

  if not state.files.root then
    build_root()
  end

  local rel_parts = vim.split(filepath:sub(#vim.fn.getcwd() + 2), '/', { trimempty = true })
  local node = state.files.root
  for i = 1, #rel_parts - 1 do
    ensure_children(node)
    node.expanded = true
    if node.children then
      for _, child in ipairs(node.children) do
        if child.name == rel_parts[i] then
          node = child
          break
        end
      end
    end
  end
  if node.type == 'directory' then
    ensure_children(node)
    node.expanded = true
  end

  M.render()

  for line, item in ipairs(state.files.display_items) do
    if item.node and item.node.abs_path == filepath then
      pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
      break
    end
  end
end

function M.stop_watchers()
  stop_all_watchers()
end

return M
