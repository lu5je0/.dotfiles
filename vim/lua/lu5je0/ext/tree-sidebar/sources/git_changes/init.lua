-- Git Changes source (Changes / Staged / Unstaged / Untracked).
local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local source_base = require('lu5je0.ext.tree-sidebar.source_base')
local render = require('lu5je0.ext.tree-sidebar.render')

local parser = require('lu5je0.ext.tree-sidebar.sources.git_changes.parser')
local locate_mod = require('lu5je0.ext.tree-sidebar.sources.git_changes.locate')

local M = {}

-- ── status → highlight tables ───────────────────────────

local LETTER_HL = {
  A = 'GitChangesAdd',
  M = 'GitChangesModify',
  D = 'GitChangesDelete',
  R = 'GitChangesRename',
  C = 'GitChangesCopy',
  T = 'GitChangesType',
  U = 'GitChangesUnmerged',
  ['?'] = 'GitChangesUntracked',
  ['!'] = 'GitChangesIgnored',
}

local function status_hl_per_char(xy, ch)
  if ch == '[' or ch == ']' or ch == ' ' then return 'GitChangesEmpty' end
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  if x == 'U' or y == 'U' or (x == y and (x == 'A' or x == 'D')) then
    return 'GitChangesUnmerged'
  end
  return LETTER_HL[ch] or 'GitChangesModify'
end

local function file_name_hl(xy)
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  if x == '?' then return 'GitFileStatusUntracked' end
  if x == 'U' or y == 'U' or (x == y and (x == 'A' or x == 'D')) then
    return 'GitFileStatusConflict'
  end
  local letter = (x ~= ' ' and x) or (y ~= ' ' and y) or ''
  if letter == 'A' then return 'GitFileStatusAdded' end
  if letter == 'D' then return 'GitFileStatusDeleted' end
  if letter == 'R' then return 'GitFileStatusRenamed' end
  if letter == 'C' then return 'GitFileStatusCopied' end
  return 'GitFileStatusModified'
end

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
    if sections[key] and #sections[key] > 0 then
      ts._dir_states[key] = ts._dir_states[key] or {}
      roots[#roots + 1] = build_section_tree(key, label, sections[key], ts._expanded[key], ts._dir_states[key])
    end
  end
  local stash_sec = build_stash_section(ts)
  if stash_sec then roots[#roots + 1] = stash_sec end
  return roots, { lines = {}, items = {}, highlights = {} }
end

function spec.render_opts(_ts, _ctx)
  return {
    compress_dirs = true,
    flat_depth = 1,
    get_dir_icon = function(node)
      if node._is_section or node._is_stash then
        return node.expanded and config.section_icons.expanded or config.section_icons.collapsed
      end
    end,
    file_suffix = function(node)
      if not node.xy then return end
      local label
      if node.section == 'staged' or node.section == 'stash' then
        label = node.xy:sub(1, 1)
      elseif node.section == 'unstaged' then
        label = node.xy:sub(2, 2)
      elseif node.section == 'untracked' then
        label = '?'
      else
        label = node.xy
      end
      local text = '[' .. label .. ']'
      local vt = {}
      for ci = 1, #text do
        local ch = text:sub(ci, ci)
        vt[#vt + 1] = { ch, status_hl_per_char(node.xy, ch) }
      end
      return text, vt
    end,
    item_data = function(node)
      if node._is_section then
        return { section = node.section, _is_section = true }
      end
      if node._is_stash then
        return { _is_stash = true, stash_ref = node.stash_ref }
      end
      local data = { xy = node.xy, path = node.rel_path or node.name, section = node.section }
      if node.stash_ref then data.stash_ref = node.stash_ref end
      return data
    end,
  }
end

function spec.decorate(ts, lines, items, highlights, virt_texts, _ctx)
  if ts._is_loading then
    return { '  Loading...' }, {}, { { line = 0, hl = 'TreeSidebarSectionName', col_start = 0, col_end = -1 } }, {}
  end

  -- Strip per-character highlights on section header lines, then paint the
  -- whole line with TreeSidebarSectionName.
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
      kept[#kept + 1] = { line = line_idx, hl = 'TreeSidebarSectionName', col_start = 0, col_end = -1 }
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

function M.refresh(callback)
  local ts = state.git_changes
  local tab_active_idx = state.active_tab_idx
  pcall(function()
    require('lu5je0.ext.tree-sidebar.actions.diff_preview').invalidate_short_head_cache()
  end)
  vim.system({ 'git', 'status', '--porcelain=v1', '-z', '--untracked-files=all' }, { text = true }, function(result)
    vim.schedule(function()
      ts.sections = parser.parse(result.stdout)
      if state:is_open() and tab_active_idx == state.active_tab_idx
          and state.active_tab_idx == config.tab_idx('git_changes') then
        M.render()
      end
      if callback then callback() end
    end)
  end)
end

function M.update_sections_from_stdout(tab_state, stdout)
  parser.update_sections_from_stdout(tab_state, stdout)
end

-- ── helpers ─────────────────────────────────────────────

function M.find_section_for_line(line)
  for i = line, 1, -1 do
    local it = state.git_changes.display_items[i]
    if it and it._is_section then return it.section end
  end
end

local function save_dir_state(line, abs_path, value)
  if not abs_path then return end
  local section_key = M.find_section_for_line(line)
  if not section_key then return end
  local ds = state.git_changes._dir_states or {}
  ds[section_key] = ds[section_key] or {}
  ds[section_key][abs_path] = value
  state.git_changes._dir_states = ds
end

-- ── open / close glue ───────────────────────────────────

local function load_stash_list(callback)
  vim.system({ 'git', 'stash', 'list', '--format=%gd%x00%gs' }, { text = true }, function(result)
    vim.schedule(function()
      local ts = state.git_changes
      local stashes = parser.parse_stash_list(result.code == 0 and result.stdout or '')
      local old = {}
      for _, s in ipairs(ts._stash_entries or {}) do old[s.ref] = s end
      for _, s in ipairs(stashes) do
        local prev = old[s.ref]
        if prev then
          s.expanded = prev.expanded
          s.children = prev.children
          s._files_loaded = prev._files_loaded
        end
      end
      ts._stash_entries = stashes
      if callback then callback() end
    end)
  end)
end

function M.reload_stash_list(after)
  if state:is_open() and state.active_tab_idx == config.tab_idx('git_changes') then
    load_stash_list(function()
      M.render()
      if after then after() end
    end)
  end
end

local function load_stash_files(stash_entry, callback)
  vim.system(
    { 'git', 'stash', 'show', '--name-status', '--find-renames', stash_entry.ref },
    { text = true },
    function(result)
      vim.schedule(function()
        local raw = parser.parse_stash_files(result.code == 0 and result.stdout or '')
        local files = {}
        for _, f in ipairs(raw) do
          local s = f.status:sub(1, 1)
          files[#files + 1] = { path = f.path, xy = s .. ' ', x = s, y = ' ', stash_ref = stash_entry.ref }
        end
        stash_entry.children = parser.files_to_tree_nodes(files, {}, 'stash')
        stash_entry._files_loaded = true
        if callback then callback() end
      end)
    end
  )
end

spec.open = {
  is_expandable = function(item)
    return item._is_section or item.node._is_stash or (item.type == 'dir' and item.node ~= nil)
  end,
  is_expanded = function(item) return item.node.expanded end,
  expand = function(item, line)
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
      save_dir_state(line, item.node.abs_path, true)
    end
  end,
  on_file = function(item)
    if item.node.abs_path then
      require('lu5je0.ext.tree-sidebar.window').open_file(item.node.abs_path)
    end
  end,
}

spec.close = {
  is_closeable = function(item)
    if item._is_section then return true end
    if item.node and item.node._is_stash and item.node.expanded then return true end
    return item.type == 'dir' and item.node and item.node.expanded
  end,
  close = function(item, line)
    if item._is_section then
      state.git_changes._expanded[item.section] = false
    elseif item.node and item.node._is_stash then
      item.node.expanded = false
      local ref = item.node.stash_ref
      for _, s in ipairs(state.git_changes._stash_entries or {}) do
        if s.ref == ref then s.expanded = false; break end
      end
    else
      item.node.expanded = false
      save_dir_state(line, item.node.abs_path, false)
    end
  end,
}

function M.open_node()
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

  source_base.open_node(spec, M.render)
end

function M.close_node()
  source_base.close_node(spec, M.render)
end

function M.collapse_all()
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

function M.expand_all()
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local section_key = M.find_section_for_line(line)
  if not section_key then return end

  local old_item = (state.git_changes.display_items or {})[line]
  state.git_changes._expanded[section_key] = true
  if state.git_changes._dir_states then
    state.git_changes._dir_states[section_key] = {}
  end
  M.render()

  local old_abs = old_item and old_item.node and old_item.node.abs_path
  if old_item then
    for i, item in ipairs(state.git_changes.display_items) do
      if old_item._is_section and item._is_section and item.section == old_item.section then
        pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
        return
      elseif old_abs and item.node and item.node.abs_path == old_abs then
        pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
        return
      end
    end
  end
  pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
end

-- ── locate ──────────────────────────────────────────────

function M.locate_file(filepath)
  locate_mod.locate_file(filepath, M.render, M.refresh, M.find_section_for_line)
end

-- ── keymaps ─────────────────────────────────────────────

function M.keymaps()
  local preview = require('lu5je0.ext.tree-sidebar.actions.preview')
  local git_ops = require('lu5je0.ext.tree-sidebar.actions.git_ops')
  return {
    { 'l', M.open_node, desc = 'Open node' },
    { '<cr>', M.open_node, desc = 'Open node' },
    { 'zo', M.open_node, desc = 'Open node' },
    { 'h', M.close_node, desc = 'Close node' },
    { 'zc', M.close_node, desc = 'Close node' },
    { 'a', git_ops.stage_file, desc = 'Stage file' },
    { 'A', git_ops.stage_section, desc = 'Stage section' },
    { 'u', git_ops.undo_last_action, desc = 'Undo' },
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
      if not item or not item.node or item._is_section then return end
      if not vim.uv.fs_stat(item.node.abs_path) then
        vim.notify('File deleted', vim.log.levels.WARN)
        return
      end
      local tabs = require('lu5je0.ext.tree-sidebar.tabs')
      tabs.switch_to(config.tab_idx('files'))
      local files = require('lu5je0.ext.tree-sidebar.sources.files')
      files.find_file(item.node.abs_path)
      vim.cmd('normal! zz')
    end, desc = 'Locate in files' },
    { 'r', function() M.refresh() end, desc = 'Refresh' },
    { '<space>', preview.toggle, desc = 'Preview' },
  }
end

return M
