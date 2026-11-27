-- Git Changes source (Changes / Staged / Unstaged / Untracked).
local state = require('lu5je0.ext.sidebar.state')
local lifecycle = require('lu5je0.ext.sidebar.lifecycle')
local config = require('lu5je0.ext.sidebar.config')
local folds = require('lu5je0.ext.sidebar.folds')
local source_base = require('lu5je0.ext.sidebar.source_base')
local render = require('lu5je0.ext.sidebar.render')
local view = require('lu5je0.ext.sidebar.view')

local parser = require('lu5je0.ext.sidebar.sources.git_changes.parser')
local locate_mod = require('lu5je0.ext.sidebar.sources.git_changes.locate')
local git_status = require('lu5je0.ext.sidebar.git_status')

local M = { preview_kind = 'diff' }

-- ── status → highlight tables ───────────────────────────

local git_style = require('lu5je0.ext.sidebar.git_style')
local file_name_hl = git_style.file_name_hl

-- ── source spec ─────────────────────────────────────────

local spec = { id = 'git_changes', state_key = 'git_changes' }
M._spec = spec

local function build_section_tree(section_key, label, files, expanded, expanded_dirs)
  return {
    name = label .. ' (' .. #files .. ')',
    type = 'directory',
    expanded = expanded,
    children = parser.files_to_tree_nodes(files, expanded_dirs, section_key),
    section = section_key,
    _is_section = true,
  }
end

-- `ts._expanded` and `ts._dir_states` are declared as nil in
-- state.new_tab_state(); fill them lazily here on first build.
local function ensure_default_state(ts)
  ts._expanded = ts._expanded or { changes = true, staged = false, unstaged = false, untracked = false, stashes = false }
  ts._dir_states = ts._dir_states or {}
end

local function stash_count_from_reflog()
  local root = parser.git_root()
  local path = root .. '/.git/logs/refs/stash'
  local ok, lines = pcall(vim.fn.readfile, path)
  if ok then return #lines end
  return 0
end

local function build_stash_section(ts)
  local stashes = ts._stash_entries or {}
  local children = {}
  for _, s in ipairs(stashes) do
    children[#children + 1] = {
      name = s.ref .. ': ' .. s.message,
      type = 'directory',
      expanded = s.expanded or false,
      children = s.children or {},
      _is_stash = true,
      stash_ref = s.ref,
      stash_message = s.message,
      _files_loaded = s._files_loaded or false,
    }
  end
  local count = #stashes > 0 and #stashes or stash_count_from_reflog()
  if count == 0 then return nil end
  local label = 'Stashes (' .. count .. ')'
  return {
    name = label,
    type = 'directory',
    expanded = ts._expanded.stashes or false,
    children = children,
    section = 'stashes',
    _is_section = true,
  }
end

function spec.build(ts, _ctx)
  local sections = ts.sections or {}
  if not sections.staged and not sections.unstaged and not sections.untracked and not sections.changes then
    -- Loading marker; rendered by post_render in `render` directly.
    ts._is_loading = true
    return {}, { lines = {}, items = {}, highlights = {} }
  end
  ts._is_loading = false

  ensure_default_state(ts)

  for _, key in ipairs({ 'staged', 'unstaged', 'untracked' }) do
    if not sections[key] or #sections[key] == 0 then
      ts._expanded[key] = false
    end
  end

  local roots = {}
  local order = {
    { 'changes', 'Changes' },
    { 'staged', 'Staged' },
    { 'unstaged', 'Unstaged' },
    { 'untracked', 'Untracked' },
  }
  for _, pair in ipairs(order) do
    local key, label = pair[1], pair[2]
    local files = sections[key] or {}
    if key == 'changes' or #files > 0 then
      ts._dir_states[key] = ts._dir_states[key] or {}
      roots[#roots + 1] = build_section_tree(key, label, files, ts._expanded[key], ts._dir_states[key])
    end
  end
  local stash_sec = build_stash_section(ts)
  if stash_sec then roots[#roots + 1] = stash_sec end
  return roots, { lines = {}, items = {}, highlights = {} }
end

function spec.render_opts()
  return git_style.tree_options({ directory_summary = true })
end

function spec.decorate(ts, lines, items, highlights, virt_texts, _ctx)
  if ts._is_loading then
    return { '  Loading...' }, {}, { { line = 0, hl = 'SidebarSectionName', col_start = 0, col_end = -1 } }, {}
  end

  -- Strip per-character highlights on section header lines, then paint the
  -- whole line with SidebarSectionName.
  local section_lines = {}
  for _, item in ipairs(items) do
    if item._is_section then section_lines[item.line_idx] = true end
  end
  if next(section_lines) then
    local kept = {}
    for _, h in ipairs(highlights) do
      if not section_lines[h.line] then kept[#kept + 1] = h end
    end
    for line_idx in pairs(section_lines) do
      kept[#kept + 1] = { line = line_idx, hl = 'SidebarSectionName', col_start = 0, col_end = -1 }
    end
    -- Replace contents in place so the source_base reference is still the same array.
    for i = 1, #highlights do highlights[i] = nil end
    for i, h in ipairs(kept) do highlights[i] = h end
  end

  -- Apply file name color for files with status info.
  for _, item in ipairs(items) do
    if item.type == 'file' and item.node and item.node.xy then
      local line_text = lines[item.line_idx + 1]
      if line_text then
        local name_hl = file_name_hl(item.node.xy)
        if name_hl then
          local icon = render.get_file_icon(item.node.name)
          local needle = icon .. ' '
          local icon_pos = line_text:find(needle, 1, true)
          if icon_pos then
            local name_start = icon_pos + #needle - 1
            highlights[#highlights + 1] = { line = item.line_idx, hl = name_hl, col_start = name_start, col_end = #line_text }
          end
        end
      end
    end
  end

  if #lines == 0 then
    return { '  No changes' }, {}, {}, {}
  end
end

-- ── render ──────────────────────────────────────────────

function M.render()
  local ts = state.git_changes
  if not ts.sections.staged and not ts.sections.unstaged and not ts.sections.untracked and not ts.sections.changes then
    -- First-time entry: paint loading marker AND kick off a refresh.
    source_base.render(spec)
    M.refresh()
    return
  end
  source_base.render(spec)
end

-- ── refresh ─────────────────────────────────────────────

function M.refresh_for(tabpage, callback)
  git_status.refresh_for(tabpage, function(success)
    git_status.render_active(tabpage)
    if callback then callback(success) end
  end)
end

function M.refresh(callback)
  M.refresh_for(vim.api.nvim_get_current_tabpage(), callback)
end

function M.update_sections_from_stdout(tab_state, stdout)
  parser.update_sections_from_stdout(tab_state, stdout)
end

-- ── helpers ─────────────────────────────────────────────

function M.find_section_for_line(line)
  local item = state.git_changes.display_items[line]
  while item do
    if item._is_section then return item.section end
    item = item.parent
  end
end

local function save_dir_state(item, abs_path, value)
  if not abs_path then return end
  local section_key = M.find_section_for_line(item.line_idx + 1)
  if not section_key then return end
  local ds = state.git_changes._dir_states or {}
  ds[section_key] = ds[section_key] or {}
  ds[section_key][abs_path] = value
  state.git_changes._dir_states = ds
end

-- ── open / close glue ───────────────────────────────────

local function run_stash(ctx, args, callback, on_cancel)
  local jobs = ctx.state.git_changes.stash_jobs
  local request = { on_cancel = on_cancel }
  jobs[request] = true
  request.job = vim.system(args, { text = true, cwd = vim.fn.getcwd() }, function(result)
    vim.schedule(function()
      jobs[request] = nil
      if lifecycle.is_current(ctx) then
        callback(result)
      end
    end)
  end)
end

function M.leave(ctx)
  local ts = ctx.state.git_changes
  ts.stash_folds.pending = false
  for request in pairs(ts.stash_jobs) do
    if request.job then
      pcall(request.job.kill, request.job)
    end
    if request.on_cancel then request.on_cancel() end
  end
  ts.stash_jobs = {}
end
M.dispose = M.leave

local function load_stash_list(callback)
  local ctx = lifecycle.capture()
  run_stash(ctx, { 'git', 'stash', 'list', '--format=%gd%x00%gs' }, function(result)
    local ts = ctx.state.git_changes
    local stashes = parser.parse_stash_list(result.code == 0 and result.stdout or '')
    local old = {}
    for _, s in ipairs(ts._stash_entries or {}) do
      old[s.ref] = s
    end
    for i, s in ipairs(stashes) do
      local prev = old[s.ref]
      if prev then
        prev.message = s.message
        stashes[i] = prev
      else
        s.expand_dirs = ts.stash_folds.expand_dirs
      end
    end
    ts._stash_entries = stashes
    if callback then
      callback()
    end
  end, function()
    local ts = ctx.state.git_changes
    if #(ts._stash_entries or {}) == 0 and ts._expanded then ts._expanded.stashes = false end
  end)
end

function M.reload_stash_list(after)
  if state:is_open() and state.active_tab_idx == config.tab_idx('git_changes') then
    load_stash_list(function()
      M.render()
      if after then
        after()
      end
    end)
  end
end

local function load_stash_files(stash_entry, callback)
  if stash_entry._files_loading then return end
  stash_entry._files_loading = true
  local ctx = lifecycle.capture()
  run_stash(ctx, { 'git', 'stash', 'show', '--name-status', '--find-renames', stash_entry.ref }, function(result)
    local raw = parser.parse_stash_files(result.code == 0 and result.stdout or '')
    local files = {}
    for _, f in ipairs(raw) do
      local s = f.status:sub(1, 1)
      files[#files + 1] = { path = f.path, xy = s .. ' ', x = s, y = ' ', stash_ref = stash_entry.ref }
    end
    stash_entry.children = parser.files_to_tree_nodes(files, {}, 'stash', nil, stash_entry.expand_dirs)
    stash_entry._files_loading = false
    stash_entry._files_loaded = true
    if callback then
      callback()
    end
  end, function()
    stash_entry._files_loading = false
    stash_entry.expanded = false
  end)
end

spec.open = {
  keep_cursor = function(item) return item._is_section or item.node._is_stash end,
  is_expandable = function(item)
    return item._is_section or item.node._is_stash or (item.type == 'dir' and item.node ~= nil)
  end,
  is_expanded = function(item) return item.node.expanded end,
  expand = function(item)
    if item._is_section then
      state.git_changes._expanded[item.section] = true
    elseif item.node._is_stash then
      item.node.expanded = true
      local ref = item.node.stash_ref
      for _, s in ipairs(state.git_changes._stash_entries or {}) do
        if s.ref == ref then s.expanded = true; break end
      end
    else
      item.node.expanded = true
      save_dir_state(item, item.node.abs_path, true)
    end
  end,
  on_file = function(item)
    if not item.node.abs_path then return end
    local xy = item.node.xy or ''
    local dominated_by_delete = false
    if item.section == 'staged' or item.section == 'stash' then
      dominated_by_delete = xy:sub(1, 1) == 'D'
    elseif item.section == 'unstaged' then
      dominated_by_delete = xy:sub(2, 2) == 'D'
    elseif item.section == 'changes' then
      dominated_by_delete = xy:sub(1, 1) == 'D' or xy:sub(2, 2) == 'D'
    end
    if dominated_by_delete then return end
    require('lu5je0.ext.sidebar.window').open_file(item.node.abs_path)
  end,
}

local function set_directory_folds(item, roots, expanded)
  local section = M.find_section_for_line(item.line_idx + 1)
  local dirs = state.git_changes._dir_states[section]
  folds.set_subtree(roots, expanded, function(node)
    if dirs and node.abs_path then dirs[node.abs_path] = expanded end
  end)
end

local function close_stash(entry)
  entry.expanded = false
  entry.expand_dirs = false
  folds.set_subtree(entry.children, false)
end

spec.close = {
  is_closeable = function(item)
    if item._is_section then return true end
    if item.node and item.node._is_stash and item.node.expanded then return true end
    return item.type == 'dir' and item.node and item.node.expanded
  end,
  close = function(item)
    if item._is_section then
      state.git_changes._expanded[item.section] = false
      if item.section == 'stashes' then state.git_changes.stash_folds.pending = false end
    elseif item.node and item.node._is_stash then
      item.node.expanded = false
      local ref = item.node.stash_ref
      for _, s in ipairs(state.git_changes._stash_entries or {}) do
        if s.ref == ref then s.expanded = false; break end
      end
    else
      local first = item.dir_chain and item.dir_chain[1] or item.node
      first.expanded = false
      save_dir_state(item, first.abs_path, false)
    end
  end,
  subtree = function(item, root)
    local ts = state.git_changes
    if item._is_section then
      ts._expanded[item.section] = false
      if item.section == 'stashes' then
        ts.stash_folds.pending = false
        ts.stash_folds.expand_dirs = false
        for _, entry in ipairs(ts._stash_entries or {}) do close_stash(entry) end
      else
        set_directory_folds(item, item.node.children, false)
      end
    elseif item.node._is_stash then
      for _, entry in ipairs(ts._stash_entries or {}) do
        if entry.ref == item.node.stash_ref then close_stash(entry); break end
      end
    else
      set_directory_folds(item, { root }, false)
    end
  end,
}

function M.open_node(fold_only)
  if not state:is_open() then return end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.git_changes.display_items[line]
  if not item then return end

  if item._is_section and item.section == 'stashes' and not item.node.expanded then
    state.git_changes._expanded.stashes = true
    load_stash_list(function() M.render() end)
    return
  end

  if item.node and item.node._is_stash and not item.node.expanded then
    local stash_ref = item.node.stash_ref
    local entry
    for _, s in ipairs(state.git_changes._stash_entries or {}) do
      if s.ref == stash_ref then entry = s; break end
    end
    if entry and not entry._files_loaded then
      entry.expanded = true
      load_stash_files(entry, function() M.render() end)
      return
    end
  end

  source_base.open_node(spec, M.render, fold_only)
end

function M.close_node()
  source_base.close_node(spec, M.render)
end

function M.collapse_all()
  state.git_changes.stash_folds.pending = false
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local old_section = M.find_section_for_line(line)

  if state.git_changes._expanded then
    for k, _ in pairs(state.git_changes._expanded) do
      state.git_changes._expanded[k] = false
    end
  end
  state.git_changes._dir_states = {}
  for _, s in ipairs(state.git_changes._stash_entries or {}) do
    s.expanded = false
  end
  M.render()

  if old_section then
    for i, item in ipairs(state.git_changes.display_items) do
      if item._is_section and item.section == old_section then
        pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
        return
      end
    end
  end
  pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
end

-- ── locate ──────────────────────────────────────────────

function M.locate(ctx, target)
  local ts = ctx.state.git_changes
  if not ts._first_located then
    ts._first_located = true
    M.locate_first_file()
  elseif vim.fn.filereadable(target.path) == 1 then
    M.locate_file(target.path)
  else
    M.render()
  end
end

function M.locate_file(filepath)
  locate_mod.locate_file(filepath, M.render, M.refresh, M.find_section_for_line)
end

-- Cursor on the first changed file; used on the first entry to this tab.
function M.locate_first_file()
  locate_mod.locate_first_file(M.render, M.refresh)
end

-- Keep the logical cursor on the same item across redraws and compression.
local function cursor_target(item)
  local target = { path = item.node.abs_path }
  while item do
    if item._is_section then
      target.section = item.section
      return target, item
    end
    if item.node._is_stash then target.ref = item.node.stash_ref end
    item = item.parent
  end
end

local function restore_target(target)
  local section, ref
  for i, item in ipairs(state.git_changes.display_items) do
    if item._is_section then section, ref = item.section, nil end
    if item.node._is_stash then ref = item.node.stash_ref end
    if section == target.section and ref == target.ref and view.item_has_path(item, target.path) then
      vim.api.nvim_win_set_cursor(state.win, { i, 0 })
      return
    end
  end
end

local function render_keep_cursor()
  local item = view.current_item(state.git_changes.display_items)
  local target = item and cursor_target(item)
  M.render()
  if target then restore_target(target) end
end

local function expand_stash(entry)
  entry.expanded = true
  entry.expand_dirs = true
  if not entry._files_loaded then
    load_stash_files(entry, render_keep_cursor)
    return
  end
  folds.set_subtree(entry.children, true)
end

local function expand_item(ts, item, section)
  if item._is_section then ts._expanded[section] = true end
  if item._is_section and section == 'stashes' then
    ts.stash_folds.expand_dirs = true
    local function expand_entries()
      for _, entry in ipairs(ts._stash_entries or {}) do expand_stash(entry) end
    end
    if #(ts._stash_entries or {}) > 0 then
      expand_entries()
    elseif not ts.stash_folds.pending then
      ts.stash_folds.pending = true
      load_stash_list(function()
        if ts.stash_folds.pending then
          ts.stash_folds.pending = false
          expand_entries()
        end
        render_keep_cursor()
      end)
    end
  elseif item.node._is_stash then
    for _, entry in ipairs(ts._stash_entries or {}) do
      if entry.ref == item.node.stash_ref then expand_stash(entry); break end
    end
  else
    set_directory_folds(item, { item.node }, true)
  end
end

local function open_folds(whole_section)
  local ts = state.git_changes
  local item = view.current_item(ts.display_items)
  if not item then return end
  if not whole_section and item.node.type ~= 'directory' then return end
  local target, section_root = cursor_target(item)
  expand_item(ts, whole_section and section_root or item, target.section)
  M.render()
  restore_target(target)
end

function M.expand_all()
  open_folds(true)
end

function M.open_node_recursive()
  open_folds(false)
end

M.folds = {
  open = function() M.open_node(true) end,
  close = M.close_node,
  open_recursive = M.open_node_recursive,
  close_subtree = function() source_base.close_subtree(spec, M.render) end,
  expand_all = M.expand_all,
  collapse_all = M.collapse_all,
}

-- ── keymaps ─────────────────────────────────────────────

function M.keymaps()
  local preview = require('lu5je0.ext.sidebar.actions.preview')
  local git_ops = require('lu5je0.ext.sidebar.actions.git_ops')
  return {
    { 'l', M.open_node, desc = 'Open node' },
    { '<cr>', M.open_node, desc = 'Open node' },
    { 'h', M.close_node, desc = 'Close node' },
    { 'a', git_ops.stage_file, desc = 'Stage file' },
    { 'A', git_ops.stage_section, desc = 'Stage section' },
    { 'u', git_ops.undo_last_action, desc = 'Undo' },
    { '<C-r>', git_ops.redo_last_action, desc = 'Redo' },
    { 'x', function()
      local line = vim.api.nvim_win_get_cursor(state.win)[1]
      local item = state.git_changes.display_items[line]
      if item and item.node and item.node._is_stash then
        git_ops.drop_stash()
      else
        git_ops.discard_file()
      end
    end, desc = 'Discard / Drop stash' },
    { 'X', git_ops.discard_section, desc = 'Discard section' },
    { '<leader>fe', function()
      local line = vim.api.nvim_win_get_cursor(state.win)[1]
      local item = state.git_changes.display_items[line]
      local path = item and item.node and item.node.abs_path
      if not path then return end
      if not vim.uv.fs_stat(path) then
        vim.notify('File deleted', vim.log.levels.WARN)
        return
      end
      local tabs = require('lu5je0.ext.sidebar.tabs')
      tabs.switch_to(config.tab_idx('files'))
      local files = require('lu5je0.ext.sidebar.sources.files')
      files.find_file(path)
      vim.cmd('normal! zz')
    end, desc = 'Locate in files' },
    { 'r', function() M.refresh() end, desc = 'Refresh' },
    { '<space>', preview.toggle, desc = 'Preview' },
    { '<space><space>', preview.enter, desc = 'Enter preview' },
    { 'd', function()
      local diff_preview = require('lu5je0.ext.sidebar.actions.diff_preview')
      local next_mode = diff_preview.toggle_mode()
      vim.notify('Diff mode: ' .. next_mode, vim.log.levels.INFO)
      preview.refresh()
    end, desc = 'Toggle diff mode (single/dual)' },
    { 'c', function()
      local diff_preview = require('lu5je0.ext.sidebar.actions.diff_preview')
      local changes_only = diff_preview.toggle_changes_only()
      vim.notify('Changes only: ' .. (changes_only and 'on' or 'off'), vim.log.levels.INFO)
      preview.refresh()
    end, desc = 'Toggle changes-only' },
    { 'yn', function()
      local line = vim.api.nvim_win_get_cursor(state.win)[1]
      local item = state.git_changes.display_items[line]
      if not item or not item.node or not item.node.name then return end
      require('lu5je0.core.clipboard').set(item.node.name)
      print('Copied: ' .. item.node.name)
    end, desc = 'Copy name' },
    { 'yp', function()
      local line = vim.api.nvim_win_get_cursor(state.win)[1]
      local item = state.git_changes.display_items[line]
      if not item or not item.node or not item.node.abs_path then return end
      require('lu5je0.core.clipboard').set(item.node.abs_path)
      print('Copied: ' .. item.node.abs_path)
    end, desc = 'Copy absolute path' },
    { 'yP', function()
      local line = vim.api.nvim_win_get_cursor(state.win)[1]
      local item = state.git_changes.display_items[line]
      if not item or not item.node or not item.node.abs_path then return end
      local rel = vim.fn.fnamemodify(item.node.abs_path, ':~:.')
      require('lu5je0.core.clipboard').set(rel)
      print('Copied: ' .. rel)
    end, desc = 'Copy relative path' },
  }
end

return M
