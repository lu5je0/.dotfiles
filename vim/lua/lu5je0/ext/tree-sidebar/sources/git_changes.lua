local state = require('lu5je0.ext.tree-sidebar.state')
local render = require('lu5je0.ext.tree-sidebar.render')
local config = require('lu5je0.ext.tree-sidebar.config')

local M = {}

-- Mirror git-status highlight groups (default=true, won't override if already loaded)
vim.api.nvim_set_hl(0, 'GitChangesAdd',       { link = '@diff.plus',  default = true })
vim.api.nvim_set_hl(0, 'GitChangesModify',    { link = 'WarningMsg',  default = true })
vim.api.nvim_set_hl(0, 'GitChangesRename',    { link = 'WarningMsg',  default = true })
vim.api.nvim_set_hl(0, 'GitChangesDelete',    { link = '@diff.minus', default = true })
vim.api.nvim_set_hl(0, 'GitChangesCopy',      { link = 'Special',     default = true })
vim.api.nvim_set_hl(0, 'GitChangesType',      { link = 'Type',        default = true })
vim.api.nvim_set_hl(0, 'GitChangesUntracked', { link = '@diff.minus', default = true })
vim.api.nvim_set_hl(0, 'GitChangesUnmerged',  { link = 'ErrorMsg',    default = true })
vim.api.nvim_set_hl(0, 'GitChangesIgnored',   { link = 'Comment',     default = true })
vim.api.nvim_set_hl(0, 'GitChangesEmpty',     { link = 'Comment',     default = true })
vim.api.nvim_set_hl(0, 'GitFileStatusAdded',     { link = '@diff.plus',  default = true })
vim.api.nvim_set_hl(0, 'GitFileStatusModified',  { link = '@diff.delta', default = true })
vim.api.nvim_set_hl(0, 'GitFileStatusRenamed',   { link = 'Special',     default = true })
vim.api.nvim_set_hl(0, 'GitFileStatusCopied',    { link = '@diff.plus',  default = true })
vim.api.nvim_set_hl(0, 'GitFileStatusDeleted',   { link = 'Comment',     default = true })
vim.api.nvim_set_hl(0, 'GitFileStatusUntracked', { link = '@diff.minus', default = true })
vim.api.nvim_set_hl(0, 'GitFileStatusConflict',  { link = 'ErrorMsg',    default = true })

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
  if ch == '[' or ch == ']' or ch == ' ' then
    return 'GitChangesEmpty'
  end
  local x = xy:sub(1, 1)
  local y = xy:sub(2, 2)
  if x == 'U' or y == 'U' or (x == y and (x == 'A' or x == 'D')) then
    return 'GitChangesUnmerged'
  end
  return LETTER_HL[ch] or 'GitChangesModify'
end

local function file_name_hl(xy)
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  if x == '?' then
    return 'GitFileStatusUntracked'
  end
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

local function parse_git_status(stdout)
  local staged = {}
  local unstaged = {}
  local untracked = {}
  local changes = {}
  local seen = {}

  if not stdout or stdout == '' then
    return { staged = staged, unstaged = unstaged, untracked = untracked, changes = changes }
  end

  local entries = vim.split(stdout, '\0', { trimempty = true })
  local i = 1
  while i <= #entries do
    local entry = entries[i]
    if #entry < 4 then
      i = i + 1
      goto continue
    end
    local xy = entry:sub(1, 2)
    local path = entry:sub(4)
    local x, y = xy:sub(1, 1), xy:sub(2, 2)

    local old_path = nil
    if x == 'R' or x == 'C' then
      i = i + 1
      old_path = entries[i]
    end

    if xy == '??' then
      untracked[#untracked + 1] = { path = path, xy = xy, old_path = old_path, x = x, y = y }
    else
      if x ~= ' ' and x ~= '?' then
        staged[#staged + 1] = { path = path, xy = xy, old_path = old_path, x = x, y = y }
      end
      if y ~= ' ' and y ~= '?' then
        unstaged[#unstaged + 1] = { path = path, xy = xy, old_path = old_path, x = x, y = y }
      end
    end

    if not seen[path] then
      seen[path] = true
      changes[#changes + 1] = { path = path, xy = xy, old_path = old_path, x = x, y = y }
    end

    i = i + 1
    ::continue::
  end
  return { staged = staged, unstaged = unstaged, untracked = untracked, changes = changes }
end

local function files_to_tree_nodes(files, expanded_dirs)
  expanded_dirs = expanded_dirs or {}
  local root_dirs = {}
  local root_files = {}

  local function get_or_create_dir(dirs_table, name, abs_prefix)
    for _, d in ipairs(dirs_table) do
      if d.name == name then
        return d
      end
    end
    local dir = {
      name = name,
      type = 'directory',
      abs_path = abs_prefix .. '/' .. name,
      expanded = true,
      children = nil,
      _subdirs = {},
      _files = {},
    }
    dirs_table[#dirs_table + 1] = dir
    return dir
  end

  local cwd = vim.fn.getcwd()
  for _, file in ipairs(files) do
    local parts = vim.split(file.path, '/', { trimempty = true })
    if #parts == 1 then
      root_files[#root_files + 1] = {
        name = parts[1],
        type = 'file',
        abs_path = cwd .. '/' .. file.path,
        rel_path = file.path,
        xy = file.xy,
        x = file.x,
        y = file.y,
        old_path = file.old_path,
      }
    else
      local current_dirs = root_dirs
      local abs_prefix = cwd
      for i = 1, #parts - 1 do
        local dir = get_or_create_dir(current_dirs, parts[i], abs_prefix)
        abs_prefix = abs_prefix .. '/' .. parts[i]
        dir.abs_path = abs_prefix
        current_dirs = dir._subdirs
      end
      -- Add file to the deepest directory
      local parent_dirs = root_dirs
      local parent_abs = cwd
      local target_dir
      for i = 1, #parts - 1 do
        for _, d in ipairs(parent_dirs) do
          if d.name == parts[i] then
            target_dir = d
            parent_abs = parent_abs .. '/' .. parts[i]
            parent_dirs = d._subdirs
            break
          end
        end
      end
      if target_dir then
        target_dir._files[#target_dir._files + 1] = {
          name = parts[#parts],
          type = 'file',
          abs_path = cwd .. '/' .. file.path,
          rel_path = file.path,
          xy = file.xy,
          x = file.x,
          y = file.y,
          old_path = file.old_path,
        }
      end
    end
  end

  -- Convert _subdirs/_files into children recursively
  local function finalize(dirs_table, files_table)
    local nodes = {}
    table.sort(dirs_table, function(a, b) return a.name < b.name end)
    table.sort(files_table, function(a, b) return a.name < b.name end)
    for _, dir in ipairs(dirs_table) do
      dir.children = finalize(dir._subdirs, dir._files)
      dir._subdirs = nil
      dir._files = nil
      -- Apply saved expanded state
      if expanded_dirs[dir.abs_path] ~= nil then
        dir.expanded = expanded_dirs[dir.abs_path]
      end
      nodes[#nodes + 1] = dir
    end
    for _, f in ipairs(files_table) do
      nodes[#nodes + 1] = f
    end
    return nodes
  end

  return finalize(root_dirs, root_files)
end


local function build_section_tree(section_key, label, files, expanded, expanded_dirs)
  return {
    name = label .. ' (' .. #files .. ')',
    type = 'directory',
    expanded = expanded,
    children = files_to_tree_nodes(files, expanded_dirs),
    section = section_key,
    _is_section = true,
  }
end

function M.render()
  local sections = state.git_changes.sections
  if not sections.staged and not sections.unstaged and not sections.untracked and not sections.changes then
    render.flush({ '  Loading...' }, {})
    M.refresh()
    return
  end

  local expanded = state.git_changes._expanded or { changes = true, staged = false, unstaged = false, untracked = false }
  state.git_changes._expanded = expanded
  local dir_states = state.git_changes._dir_states or {}
  state.git_changes._dir_states = dir_states

  local root_nodes = {}
  if sections.changes and #sections.changes > 0 then
    dir_states.changes = dir_states.changes or {}
    root_nodes[#root_nodes + 1] = build_section_tree('changes', 'Changes', sections.changes, expanded.changes, dir_states.changes)
  end
  if sections.staged and #sections.staged > 0 then
    dir_states.staged = dir_states.staged or {}
    root_nodes[#root_nodes + 1] = build_section_tree('staged', 'Staged', sections.staged, expanded.staged, dir_states.staged)
  end
  if sections.unstaged and #sections.unstaged > 0 then
    dir_states.unstaged = dir_states.unstaged or {}
    root_nodes[#root_nodes + 1] = build_section_tree('unstaged', 'Unstaged', sections.unstaged, expanded.unstaged, dir_states.unstaged)
  end
  if sections.untracked and #sections.untracked > 0 then
    dir_states.untracked = dir_states.untracked or {}
    root_nodes[#root_nodes + 1] = build_section_tree('untracked', 'Untracked', sections.untracked, expanded.untracked, dir_states.untracked)
  end

  local lines, items, highlights = render.render_tree(root_nodes, {
    compress_dirs = true,
    flat_depth = 1,
    get_dir_icon = function(node)
      if node._is_section then
        local arrow = node.expanded and '' or ''
        return arrow
      end
      return nil
    end,
    file_suffix = function(node)
      if node.xy then
        return '[' .. node.xy .. ']', nil
      end
      return nil, nil
    end,
    item_data = function(node)
      if node._is_section then
        return { section = node.section, _is_section = true }
      end
      return { xy = node.xy, path = node.rel_path or node.name, section = nil }
    end,
  })

  -- Apply section-level and per-char highlights
  for _, item in ipairs(items) do
    if item._is_section then
      -- Replace all highlights for section line with per-section hl
      local new_hl = {}
      for _, h in ipairs(highlights) do
        if h.line ~= item.line_idx then
          new_hl[#new_hl + 1] = h
        end
      end
      highlights = new_hl
      highlights[#highlights + 1] = { line = item.line_idx, hl = 'TreeSidebarSectionName', col_start = 0, col_end = -1 }
    elseif item.type == 'file' and item.node and item.node.xy then
      local line_text = lines[item.line_idx + 1]
      if line_text then
        -- Per-char highlight for [XY] suffix
        local bracket_start = line_text:find('%[', 1, true)
        if bracket_start then
          for ci = bracket_start, #line_text do
            local ch = line_text:sub(ci, ci)
            local hl = status_hl_per_char(item.node.xy, ch)
            highlights[#highlights + 1] = { line = item.line_idx, hl = hl, col_start = ci - 1, col_end = ci }
          end
        end
        -- File name highlight
        local name_hl = file_name_hl(item.node.xy)
        if name_hl then
          local icon = render.get_file_icon(item.node.name)
          local icon_end_pattern = icon .. ' '
          local icon_pos = line_text:find(icon_end_pattern, 1, true)
          if icon_pos then
            local name_start = icon_pos + #icon_end_pattern - 1
            local name_end = bracket_start and (bracket_start - 3) or #line_text
            if name_end > name_start then
              highlights[#highlights + 1] = { line = item.line_idx, hl = name_hl, col_start = name_start, col_end = name_end }
            end
          end
        end
      end
    end
  end

  if #lines == 0 then
    lines = { '  No changes' }
    items = {}
    highlights = {}
  end

  state.git_changes.display_items = items
  render.flush(lines, highlights)
end

function M.refresh(callback)
  vim.system({ 'git', 'status', '--porcelain=v1', '-z', '--untracked-files=all' }, { text = true }, function(result)
    vim.schedule(function()
      state.git_changes.sections = parse_git_status(result.stdout)
      if state:is_open() and state.active_tab_idx == 2 then
        M.render()
      end
      if callback then
        callback()
      end
    end)
  end)
end

function M.find_section_for_line(line)
  for i = line, 1, -1 do
    local it = state.git_changes.display_items[i]
    if it and it._is_section then
      return it.section
    end
  end
  return nil
end

local function save_dir_state(line, abs_path, value)
  if not abs_path then
    return
  end
  local section_key = M.find_section_for_line(line)
  if not section_key then
    return
  end
  local dir_states = state.git_changes._dir_states or {}
  dir_states[section_key] = dir_states[section_key] or {}
  dir_states[section_key][abs_path] = value
  state.git_changes._dir_states = dir_states
end

function M.open_node()
  render.open_node({
    get_items = function() return state.git_changes.display_items end,
    render_fn = M.render,
    is_expandable = function(item)
      return item._is_section or (item.type == 'dir' and item.node ~= nil)
    end,
    is_expanded = function(item) return item.node.expanded end,
    expand = function(item, line)
      if item._is_section then
        state.git_changes._expanded[item.section] = true
      else
        item.node.expanded = true
        save_dir_state(line, item.node.abs_path, true)
      end
    end,
    on_file = function(item)
      vim.cmd('wincmd p')
      vim.cmd('edit ' .. vim.fn.fnameescape(item.node.abs_path))
    end,
  })
end

function M.close_node()
  render.close_node({
    get_items = function() return state.git_changes.display_items end,
    render_fn = M.render,
    is_closeable = function(item)
      if item._is_section then return true end
      return item.type == 'dir' and item.node and item.node.expanded
    end,
    close = function(item, line)
      if item._is_section then
        state.git_changes._expanded[item.section] = false
      else
        item.node.expanded = false
        save_dir_state(line, item.node.abs_path, false)
      end
    end,
  })
end

-- ── git operations (delegated to actions/git_ops.lua) ───

function M.locate_file(filepath)
  if not filepath or filepath == '' then
    return
  end

  local cwd = vim.fn.getcwd()
  if not vim.startswith(filepath, cwd .. '/') then
    return
  end
  local rel_path = filepath:sub(#cwd + 2)

  local sections = state.git_changes.sections
  if not sections.changes then
    sections.changes = {}
  end

  local found_in_changes = false
  for _, f in ipairs(sections.changes) do
    if f.path == rel_path then
      found_in_changes = true
      break
    end
  end

  if not found_in_changes then
    table.insert(sections.changes, {
      path = rel_path,
      xy = '  ',
      x = ' ',
      y = ' ',
      old_path = nil,
      _temporary = true,
    })
  end

  local expanded = state.git_changes._expanded or { changes = true, staged = false, unstaged = false, untracked = false }
  expanded.changes = true
  state.git_changes._expanded = expanded

  local dir_states = state.git_changes._dir_states or {}
  dir_states.changes = dir_states.changes or {}
  state.git_changes._dir_states = dir_states
  local parts = vim.split(rel_path, '/', { trimempty = true })
  local abs_prefix = cwd
  for i = 1, #parts - 1 do
    abs_prefix = abs_prefix .. '/' .. parts[i]
    dir_states.changes[abs_prefix] = true
  end

  M.render()

  local items = state.git_changes.display_items or {}
  for line, item in ipairs(items) do
    if item.type == 'file' and item.node and item.node.abs_path == filepath then
      pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
      return
    end
  end
end

function M.keymaps()
  local preview_mod = require('lu5je0.ext.tree-sidebar.actions.preview')
  local git_ops_actions = require('lu5je0.ext.tree-sidebar.actions.git_ops')
  return {
    { 'l', M.open_node, desc = 'Open node' },
    { '<cr>', M.open_node, desc = 'Open node' },
    { 'h', M.close_node, desc = 'Close node' },
    { 'a', git_ops_actions.stage_file, desc = 'Stage file' },
    { 'A', git_ops_actions.stage_section, desc = 'Stage section' },
    { 'u', git_ops_actions.unstage_file, desc = 'Unstage file' },
    { 'x', git_ops_actions.discard_file, desc = 'Discard file' },
    { 'X', git_ops_actions.discard_section, desc = 'Discard section' },
    { 'U', git_ops_actions.undo_last_action, desc = 'Undo' },
    { 'r', function() M.refresh() end, desc = 'Refresh' },
    { '<space>', preview_mod.toggle, desc = 'Preview' },
  }
end

return M
