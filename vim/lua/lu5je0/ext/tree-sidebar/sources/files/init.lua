-- Files source: workspace file tree.
local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local source_base = require('lu5je0.ext.tree-sidebar.source_base')
local view = require('lu5je0.ext.tree-sidebar.view')

local tree = require('lu5je0.ext.tree-sidebar.sources.files.tree')
local watcher = require('lu5je0.ext.tree-sidebar.watcher')
local git = require('lu5je0.ext.tree-sidebar.sources.files.git')
local info = require('lu5je0.ext.tree-sidebar.sources.files.info')

local M = {}

-- ── source spec ─────────────────────────────────────────

local spec = { id = 'files', state_key = 'files' }
M._spec = spec

local function ensure_root()
  if not state.files.root or state.files.root.abs_path ~= vim.fn.getcwd() then
    tree.build_root()
  end
end

local function file_suffix(node)
  local key = tree.rel_to_cwd(node.abs_path)
  local g = state.files.git_status_map[key]
  if g then return g.glyph, g.hl end
end

local function dir_suffix(node)
  local key = tree.rel_to_cwd(node.abs_path) .. '/'
  local g = state.files.git_status_map[key]
  if g then return g.glyph, g.hl end
end

local function dotfile_hl(node)
  if tree.is_dotfile(node.name) then
    return 'TreeSidebarDotfile'
  end
end

function spec.build(ts, _ctx)
  ensure_root()
  tree.prepare_tree(ts.root)

  local cwd = vim.fn.getcwd()
  local header = { lines = {}, items = {}, highlights = {} }
  if cwd ~= '/' then
    header.lines[1] = vim.fn.fnamemodify(cwd, ':~') .. '/..'
    header.items[1] = { type = 'root', node = ts.root, line_idx = 0 }
    header.highlights[1] = { line = 0, hl = 'TreeSidebarRootFolder', col_start = 0, col_end = -1 }
  end
  if ts.live_filter then
    local prefix = '[FILTER]: '
    local filter_line = prefix .. '/' .. ts.live_filter .. '/'
    local idx = #header.lines + 1
    local line_idx = idx - 1
    header.lines[idx] = filter_line
    header.items[idx] = { type = 'filter', line_idx = line_idx }
    header.highlights[#header.highlights + 1] = { line = line_idx, hl = 'TreeSidebarLiveFilterPrefix', col_start = 0, col_end = #prefix }
    header.highlights[#header.highlights + 1] = { line = line_idx, hl = 'TreeSidebarLiveFilterValue', col_start = #prefix, col_end = #filter_line }
  end
  return ts.root.children or {}, header
end

function spec.render_opts(ts, ctx)
  local reveal = ctx.reveal_path or ts.reveal_path
  return {
    filter = tree.make_filter(reveal),
    file_suffix = file_suffix,
    dir_suffix = dir_suffix,
    node_hl = dotfile_hl,
    compress_dirs = ts.compress_dirs or false,
  }
end

function spec.post_flush(_ts, _ctx)
  watcher.sync_files(vim.api.nvim_get_current_tabpage())
  require('lu5je0.ext.tree-sidebar.actions.file_ops').apply_clipboard_mark()
end

-- ── public render ───────────────────────────────────────

function M.render(opts)
  source_base.render(spec, opts or {})
end

-- Invoked by watcher.lua after a fs_event debounce. The timer may fire
-- after the user switched tabs, so we explicitly target the originating
-- tabpage's state and only repaint when still on that tab.
watcher.on_files_changed = function(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
  local ts = state.tab_for(tabpage).files
  if ts.root then
    tree.rescan_node(ts.root)
  end
  ts.reveal_path = nil
  git.refresh_for(tabpage, function()
    if vim.api.nvim_get_current_tabpage() == tabpage and state:is_open() then
      if state.active_tab_idx == config.tab_idx('files') then
        M.render()
      elseif state.active_tab_idx == config.tab_idx('git_changes') then
        require('lu5je0.ext.tree-sidebar.sources.git_changes').refresh()
      end
    end
  end)
end

-- ── open / close glue ───────────────────────────────────

local function compress_descend(node)
  local filter = tree.make_filter(state.files.reveal_path)
  while node.children do
    local visible_dir = nil
    local visible_count = 0
    for _, c in ipairs(node.children) do
      if filter(c) then
        visible_count = visible_count + 1
        if visible_count > 1 then break end
        if c.type == 'directory' then
          visible_dir = c
        end
      end
    end
    if visible_count ~= 1 or not visible_dir then break end
    tree.ensure_children(visible_dir)
    visible_dir.expanded = true
    node = visible_dir
  end
end

spec.open = {
  is_expandable = function(it) return it.type == 'dir' end,
  is_expanded = function(it) return it.node.expanded end,
  expand = function(it)
    tree.ensure_children(it.node)
    it.node.expanded = true
    if state.files.compress_dirs then
      compress_descend(it.node)
    end
  end,
  on_already_expanded = function(item)
    local items = state.files.display_items
    local cur_line = vim.api.nvim_win_get_cursor(state.win)[1]
    local next_item = items[cur_line + 1]
    if not next_item or next_item.type == 'root' or next_item.type == 'filter'
      or (next_item.node and next_item.node.abs_path
        and not vim.startswith(next_item.node.abs_path, item.node.abs_path .. '/')) then
      return
    end
    local target = require('lu5je0.ext.tree-sidebar.window').get_target_win()
    if target then vim.api.nvim_set_current_win(target) end
  end,
  on_file = function(it)
    require('lu5je0.ext.tree-sidebar.window').open_file(it.node.abs_path)
  end,
}

spec.close = {
  is_closeable = function(it) return it.type == 'dir' and it.node.expanded end,
  close = function(it) it.node.expanded = false end,
  is_boundary = function(it) return it.type == 'root' end,
}

function M.open_node()
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.files.display_items[line]
  if item and item.type == 'root' then
    M.cd_parent()
    return
  end
  source_base.open_node(spec, M.render)
end

function M.close_node()
  source_base.close_node(spec, M.render)
end

-- ── cwd / cursor management ─────────────────────────────

function M.save_cursor_for_cwd()
  if not state:is_open() then return end
  state.files._cursor_cache = state.files._cursor_cache or {}
  state.files._cursor_cache[vim.fn.getcwd()] = vim.api.nvim_win_get_cursor(state.win)
end

function M.restore_cursor_for_cwd()
  local cache = state.files._cursor_cache
  if cache and cache[vim.fn.getcwd()] then
    pcall(vim.api.nvim_win_set_cursor, state.win, cache[vim.fn.getcwd()])
  else
    pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
  end
end

local function cd_to(path)
  M.save_cursor_for_cwd()
  state.files.reveal_path = nil
  vim.cmd('cd ' .. vim.fn.fnameescape(path))
  pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
end

function M.cd_to_node()
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.files.display_items[line]
  if not item then return end
  local path
  if item.type == 'dir' or item.type == 'root' then
    path = item.node.abs_path
  elseif item.type == 'file' then
    path = vim.fs.dirname(item.node.abs_path)
  end
  if path then cd_to(path) end
end

function M.cd_parent()
  local cwd = vim.fn.getcwd()
  local parent = vim.fs.dirname(cwd)
  if parent and parent ~= cwd then cd_to(parent) end
end

function M.cd_home()
  cd_to(vim.fn.expand('~'))
end

-- ── refresh ─────────────────────────────────────────────

function M.refresh()
  state.files.reveal_path = nil
  if state.files.root then
    tree.rescan_node(state.files.root)
  else
    tree.build_root()
  end
  M.render()
  M.refresh_git_status(M.render)
end

function M.refresh_git_status(callback)
  git.refresh(callback)
end

function M.update_git_status_from_stdout(tab_files, stdout)
  git.update_from_stdout(tab_files, stdout)
end

-- ── toggles ─────────────────────────────────────────────

function M.toggle_dotfiles()
  local old_line = vim.api.nvim_win_get_cursor(state.win)[1]
  local old_item = state.files.display_items[old_line]
  local old_path = old_item and old_item.node and old_item.node.abs_path

  state.files.hide_dotfiles = not state.files.hide_dotfiles
  state.files.reveal_path = nil
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

function M.toggle_compress_dirs()
  state.files.compress_dirs = not state.files.compress_dirs
  vim.notify('Group empty: ' .. (state.files.compress_dirs and 'on' or 'off'), vim.log.levels.INFO)
  M.render()
end

-- ── git-change navigation ───────────────────────────────

function M.next_git_file()
  if not state:is_open() then return end
  local cwd = vim.fn.getcwd()
  local cur = vim.api.nvim_win_get_cursor(state.win)[1]
  local start = cur + 1
  local cur_item = state.files.display_items[cur]
  if cur_item and cur_item.type == 'dir' and git.is_git_item(cur_item, cwd) and not cur_item.node.expanded then
    start = cur
  end
  for _ = 1, 50 do
    local items = state.files.display_items
    local found_dir = false
    for i = start, #items do
      local item = items[i]
      if git.is_git_item(item, cwd) then
        if item.type == 'file' then
          pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
          return
        else
          tree.ensure_children(item.node)
          item.node.expanded = true
          M.render()
          start = i + 1
          found_dir = true
          break
        end
      end
    end
    if not found_dir then return end
  end
end

function M.prev_git_file()
  if not state:is_open() then return end
  local cwd = vim.fn.getcwd()
  local cur = vim.api.nvim_win_get_cursor(state.win)[1]
  local items = state.files.display_items
  for i = cur - 1, 1, -1 do
    if git.is_git_item(items[i], cwd) then
      pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
      return
    end
  end
end

-- ── collapse all ────────────────────────────────────────

function M.collapse_all()
  local old_items = state.files.display_items or {}
  local function collapse(node)
    if node.type == 'directory' and node.expanded then node.expanded = false end
    if node.children then
      for _, child in ipairs(node.children) do collapse(child) end
    end
  end
  if state.files.root then
    for _, child in ipairs(state.files.root.children or {}) do collapse(child) end
  end
  M.render()
  view.restore_cursor(old_items, state.files.display_items)
end

-- ── show file info ──────────────────────────────────────

M.show_file_info = info.show

function M.stop_watchers()
  watcher.release(state.tab())
end

-- ── find_file (reveal) ──────────────────────────────────

function M.find_file(filepath)
  if not filepath or filepath == '' then return end

  local cwd = vim.fn.getcwd()
  local dir = vim.fs.dirname(filepath)
  if not vim.startswith(dir, cwd) then
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))
    state.files.root = nil
  end

  ensure_root()

  local rel_parts = vim.split(tree.rel_to_cwd(filepath), '/', { trimempty = true })
  local node = state.files.root
  for i = 1, #rel_parts - 1 do
    tree.ensure_children(node)
    node.expanded = true
    if node.children then
      for _, child in ipairs(node.children) do
        if child.name == rel_parts[i] then node = child; break end
      end
    end
  end
  if node.type == 'directory' then
    tree.ensure_children(node)
    node.expanded = true
  end

  state.files.reveal_path = filepath
  M.render({ reveal_path = filepath })

  for line, item in ipairs(state.files.display_items) do
    if item.node and item.node.abs_path == filepath then
      pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
      return
    end
  end
  vim.notify(
    string.format('[tree-sidebar] find_file failed\n  filepath: %s\n  cwd: %s\n  items: %d',
      filepath, vim.fn.getcwd(), #state.files.display_items),
    vim.log.levels.DEBUG)
end

-- ── keymaps ─────────────────────────────────────────────

function M.keymaps()
  local nav = require('lu5je0.ext.tree-sidebar.actions.navigation')
  local file_ops = require('lu5je0.ext.tree-sidebar.actions.file_ops')
  local preview = require('lu5je0.ext.tree-sidebar.actions.preview')
  local live_filter = require('lu5je0.ext.tree-sidebar.sources.files.live_filter')

  return {
    { 'l', M.open_node, desc = 'Open node' },
    { '<cr>', M.open_node, desc = 'Open node' },
    { 'zo', M.open_node, desc = 'Open node' },
    { 'u', M.cd_parent, desc = 'Navigate up' },
    { 'h', M.close_node, desc = 'Close node' },
    { 'zc', M.close_node, desc = 'Close node' },
    { '-', M.cd_parent, desc = 'Navigate up' },
    { '<bs>', M.cd_parent, desc = 'Navigate up' },
    { 'cd', M.cd_to_node, desc = 'CD to node' },
    { 'H', M.cd_home, desc = 'CD home' },
    { '<c-o>', nav.back, desc = 'Back' },
    { '<c-i>', nav.forward, desc = 'Forward' },
    { 'I', M.toggle_dotfiles, desc = 'Toggle dotfiles' },
    { 'gC', M.toggle_compress_dirs, desc = 'Toggle group empty' },
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
    { 'gx', file_ops.system_open, desc = 'System open' },
    { ']g', M.next_git_file, desc = 'Next git change' },
    { '[g', M.prev_git_file, desc = 'Prev git change' },
    { 'f', live_filter.start, desc = 'Filter' },
    { 'F', live_filter.clear, desc = 'Clear filter' },
    { 'o', function()
      local item = state.files.display_items[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not item or not item.node then return end
      local dir = item.node.type == 'directory' and item.node.abs_path or vim.fs.dirname(item.node.abs_path)
      local win = require('lu5je0.ext.tree-sidebar.window')
      local target = win.get_target_win()
      if not target then
        vim.cmd('belowright vsplit')
      else
        vim.api.nvim_set_current_win(target)
      end
      vim.cmd('Oil ' .. vim.fn.fnameescape(dir))
    end, desc = 'Oil' },
    { '<space>', preview.toggle, desc = 'Preview' },
    { 't', function()
      local item = state.files.display_items[vim.api.nvim_win_get_cursor(state.win)[1]]
      if not item or not item.node then return end
      local dir = item.node.type == 'directory' and item.node.abs_path or vim.fs.dirname(item.node.abs_path)
      require('lu5je0.ext.terminal').send_to_terminal('cd "' .. dir .. '"', { go_back = 0 })
    end, desc = 'Open terminal' },
  }
end

-- ── test-suite hooks (stable underscored names) ─────────

M._build_git_status_map = git.build_status_map
M._git_status_to_glyph = git.status_to_glyph

return M
