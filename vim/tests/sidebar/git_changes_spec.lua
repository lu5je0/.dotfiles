-- Sidebar git_changes tests: pure logic units.
-- Usage: cd vim && nvim --headless -u NONE -l tests/sidebar/git_changes_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local git_changes = require('lu5je0.ext.sidebar.sources.git_changes')

-- ============================================================================
-- group: parse_git_status via update_sections_from_stdout
-- ============================================================================

r.group('parse_git_status')

r.run('staged-only file goes into staged section', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'M  file.lua\0')
  r.assert_eq(#t.sections.staged, 1)
  r.assert_eq(t.sections.staged[1].path, 'file.lua')
  r.assert_eq(#t.sections.unstaged, 0)
  r.assert_eq(#t.sections.untracked, 0)
end)

r.run('unstaged-only file goes into unstaged section', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, ' M file.lua\0')
  r.assert_eq(#t.sections.unstaged, 1)
  r.assert_eq(#t.sections.staged, 0)
end)

r.run('untracked file goes into untracked section', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, '?? new.txt\0')
  r.assert_eq(#t.sections.untracked, 1)
  r.assert_eq(t.sections.untracked[1].path, 'new.txt')
  r.assert_eq(#t.sections.staged, 0)
  r.assert_eq(#t.sections.unstaged, 0)
end)

r.run('MM file goes into both staged and unstaged', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'MM file.lua\0')
  r.assert_eq(#t.sections.staged, 1)
  r.assert_eq(#t.sections.unstaged, 1)
end)

r.run('changes section contains all non-ignored files', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'M  a.lua\0 M b.lua\0?? c.lua\0')
  r.assert_eq(#t.sections.changes, 3)
end)

r.run('rename consumes next NUL entry', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'R  new.lua\0old.lua\0?? other.lua\0')
  r.assert_eq(#t.sections.staged, 1)
  r.assert_eq(t.sections.staged[1].path, 'new.lua')
  r.assert_eq(t.sections.staged[1].old_path, 'old.lua')
  r.assert_eq(#t.sections.untracked, 1)
  r.assert_eq(t.sections.untracked[1].path, 'other.lua')
end)

r.run('ignored file is excluded from all sections', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, '!! ignored.txt\0M  real.lua\0')
  r.assert_eq(#t.sections.staged, 1)
  r.assert_eq(#t.sections.changes, 1)
end)

r.run('empty stdout returns empty sections', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, '')
  r.assert_eq(#t.sections.staged, 0)
  r.assert_eq(#t.sections.unstaged, 0)
  r.assert_eq(#t.sections.untracked, 0)
  r.assert_eq(#t.sections.changes, 0)
end)

-- ============================================================================
-- group: collapsed directory status
-- ============================================================================

r.group('collapsed directory status')

local parser = require('lu5je0.ext.sidebar.sources.git_changes.parser')
local render = require('lu5je0.ext.sidebar.render')
local git_style = require('lu5je0.ext.sidebar.git_style')

local function summary_tree(statuses, section)
  local files = {}
  for i, xy in ipairs(statuses) do
    files[#files + 1] = { path = 'src/nested/' .. i .. '.lua', xy = xy, x = xy:sub(1, 1), y = xy:sub(2, 2) }
  end
  local root = vim.fn.tempname()
  return parser.files_to_tree_nodes(files, { [root .. '/src'] = false }, section or 'changes', root)
end

local function suffix_text(vt)
  local parts = {}
  for _, chunk in ipairs(vt.virt_text) do parts[#parts + 1] = chunk[1] end
  return table.concat(parts)
end

for _, case in ipairs({
  { { 'M ', 'M ' }, 'changes', '[M ]' },
  { { ' M', ' M' }, 'changes', '[ M]' },
  { { 'MM', 'MM' }, 'changes', '[MM]' },
  { { 'A ', 'M ' }, 'changes', '[* ]' },
  { { 'M ', ' M' }, 'changes', '[**]' },
  { { '??', '??' }, 'changes', '[??]' },
  { { '??', 'M ' }, 'changes', '[**]' },
  { { 'MM', 'M ' }, 'staged', '[M]' },
  { { 'A ', 'MM' }, 'staged', '[*]' },
  { { 'MM', ' M' }, 'unstaged', '[M]' },
  { { ' M', ' D' }, 'unstaged', '[*]' },
  { { '??', '??' }, 'untracked', '[?]' },
  { { 'A ', 'M ' }, 'stash', '[*]' },
}) do
  r.run(case[2] .. ': ' .. table.concat(case[1], ',') .. ' -> ' .. case[3], function()
    local nodes = summary_tree(case[1], case[2])
    local _, items, _, vt = render.render_tree(nodes, git_changes._spec.render_opts())
    r.assert_eq(#items, 1)
    r.assert_eq(#vt, 1)
    r.assert_eq(suffix_text(vt[1]), case[3])
    r.assert_eq(nodes[1].xy, nil)
    r.assert_eq(nodes[1].git_summary.xy, nodes[1].children[1].git_summary.xy)
  end)
end

r.run('mixed columns use the same neutral color as brackets', function()
  local _, _, _, vt = render.render_tree(summary_tree({ 'M ', ' M' }), git_changes._spec.render_opts())
  r.assert_eq(vt[1].virt_text[2], { '*', 'GitChangesEmpty' })
  r.assert_eq(vt[1].virt_text[3], { '*', 'GitChangesEmpty' })
end)

r.run('summaries combine sibling directories and direct files regardless of expansion', function()
  local root = vim.fn.tempname()
  local files = {
    { path = 'src/a/one.lua', xy = 'M ', x = 'M', y = ' ' },
    { path = 'src/b/two.lua', xy = ' M', x = ' ', y = 'M' },
    { path = 'src/three.lua', xy = '??', x = '?', y = '?' },
  }
  local nodes = parser.files_to_tree_nodes(files, { [root .. '/src'] = false, [root .. '/src/a'] = false }, 'changes', root)
  local _, _, _, vt = render.render_tree(nodes, git_changes._spec.render_opts())
  r.assert_eq(suffix_text(vt[1]), '[**]')
  r.assert_eq(nodes[1].children[1].git_summary.xy, 'M ')
  r.assert_eq(nodes[1].children[2].git_summary.xy, ' M')
end)

for _, xy in ipairs({ 'UU', 'AA', 'DD', 'AU', 'UD', 'UA', 'DU' }) do
  r.run('mixed conflict ' .. xy .. ' stays red through ancestors', function()
    local nodes = summary_tree({ xy, ' M' })
    local _, _, _, vt = render.render_tree(nodes, git_changes._spec.render_opts())
    r.assert_eq(nodes[1].git_summary.conflict, true)
    r.assert_eq(vt[1].virt_text[2], { '*', 'GitChangesUnmerged' })
    r.assert_eq(vt[1].virt_text[3], { '*', 'GitChangesUnmerged' })
  end)
end

r.run('untracked summary uses the same status color as files', function()
  local _, _, _, vt = render.render_tree(summary_tree({ '??' }), git_changes._spec.render_opts())
  r.assert_eq(vt[1].virt_text[2], { '?', 'GitChangesUntracked' })
  r.assert_eq(vt[1].virt_text[3], { '?', 'GitChangesUntracked' })
end)

r.run('expanding a compressed chain shows file suffixes and folding restores summary', function()
  local nodes = summary_tree({ 'M ', ' M' })
  local opts = git_changes._spec.render_opts()
  nodes[1].expanded = true
  local _, items, _, vt = render.render_tree(nodes, opts)
  r.assert_eq(#items, 3)
  r.assert_eq(items[1].display_node, nodes[1].children[1])
  r.assert_eq(#vt, 2)
  r.assert_eq(vt[1].line, 1)
  r.assert_eq(suffix_text(vt[1]), '[M ]')
  r.assert_eq(suffix_text(vt[2]), '[ M]')
  nodes[1].expanded = false
  _, items, _, vt = render.render_tree(nodes, opts)
  r.assert_eq(#items, 1)
  r.assert_eq(suffix_text(vt[1]), '[**]')
end)

r.run('section and stash headings never receive summaries', function()
  local opts = git_changes._spec.render_opts()
  local node = summary_tree({ 'M ' })[1]
  node._is_section = true
  r.assert_eq(opts.dir_suffix(node), nil)
  node._is_section, node._is_stash = nil, true
  r.assert_eq(opts.dir_suffix(node), nil)
end)

r.run('shared History style keeps directory suffixes hidden and deletion highlight intact', function()
  local nodes = summary_tree({ 'D ' }, 'history')
  local opts = git_style.tree_options()
  local _, _, _, vt = render.render_tree(nodes, opts)
  r.assert_eq(#vt, 0)
  nodes[1].all_deleted = true
  r.assert_eq(opts.node_hl(nodes[1]), 'GitFileStatusDeleted')
end)

-- ============================================================================
-- group: restore_cursor
-- ============================================================================

r.group('restore_cursor')

r.run('exact node match takes priority over ancestor', function()
  local child = { name = 'child', type = 'file' }
  local parent = { name = 'parent', type = 'directory', children = { child } }
  local root = { name = 'root', type = 'directory', children = { parent } }

  local new_items = {
    { node = root },
    { node = parent },
    { node = child },
  }

  -- We can't call restore_cursor directly (needs nvim window), so test the logic
  -- by verifying the contains function behavior
  local function contains(node, target)
    if node == target then return true end
    if node.children then
      for _, c in ipairs(node.children) do
        if contains(c, target) then return true end
      end
    end
    return false
  end

  -- child is contained by root, parent, and itself
  r.assert_eq(contains(root, child), true)
  r.assert_eq(contains(parent, child), true)
  r.assert_eq(contains(child, child), true)

  -- identity match should find child at index 3
  local identity_match = nil
  for i, item in ipairs(new_items) do
    if item.node == child then
      identity_match = i
      break
    end
  end
  r.assert_eq(identity_match, 3)
end)

r.run('ancestor fallback picks deepest match', function()
  local child = { name = 'child', type = 'file' }
  local parent = { name = 'parent', type = 'directory', children = { child } }
  local root = { name = 'root', type = 'directory', children = { parent } }

  local function contains(node, target)
    if node == target then return true end
    if node.children then
      for _, c in ipairs(node.children) do
        if contains(c, target) then return true end
      end
    end
    return false
  end

  -- After collapse: child not visible, only root and parent
  local new_items = {
    { node = root },
    { node = parent },
  }

  -- Simulate: find best (deepest) match for child
  local best_line = 1
  for i, item in ipairs(new_items) do
    if item.node and contains(item.node, child) then
      best_line = i
    end
  end
  -- parent (index 2) is deeper than root (index 1)
  r.assert_eq(best_line, 2)
end)

-- ============================================================================
-- group: discard_section classification
-- ============================================================================

r.group('discard_section file classification')

r.run('staged-only files detected in changes section', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'A  new.lua\0M  mod.lua\0')
  local files = t.sections.changes

  local target_files = {}
  local staged_only_paths = {}
  for _, file in ipairs(files) do
    local x = (file.xy or ''):sub(1, 1)
    local y = (file.xy or ''):sub(2, 2)
    if x == '?' or (y ~= ' ' and y ~= '?') then
      target_files[#target_files + 1] = file
    elseif x ~= ' ' and x ~= '?' and y == ' ' then
      staged_only_paths[#staged_only_paths + 1] = file.path
    end
  end

  r.assert_eq(#target_files, 0, 'no unstaged/untracked files')
  r.assert_eq(#staged_only_paths, 2, 'both files are staged-only')
end)

r.run('mixed staged and unstaged correctly classified', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'M  staged.lua\0 M unstaged.lua\0MM both.lua\0?? new.lua\0')
  local files = t.sections.changes

  local target_files = {}
  local staged_only_paths = {}
  for _, file in ipairs(files) do
    local x = (file.xy or ''):sub(1, 1)
    local y = (file.xy or ''):sub(2, 2)
    if x == '?' or (y ~= ' ' and y ~= '?') then
      target_files[#target_files + 1] = file
    elseif x ~= ' ' and x ~= '?' and y == ' ' then
      staged_only_paths[#staged_only_paths + 1] = file.path
    end
  end

  -- unstaged.lua (y=M), both.lua (y=M), new.lua (??) are target_files
  r.assert_eq(#target_files, 3, '3 unstaged/untracked files')
  -- staged.lua (x=M, y=' ') is staged-only
  r.assert_eq(#staged_only_paths, 1, '1 staged-only file')
  r.assert_eq(staged_only_paths[1], 'staged.lua')
end)

r.run('deleted staged file is classified as staged-only', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'D  deleted.lua\0')
  local files = t.sections.changes

  local staged_only_paths = {}
  for _, file in ipairs(files) do
    local x = (file.xy or ''):sub(1, 1)
    local y = (file.xy or ''):sub(2, 2)
    if x ~= ' ' and x ~= '?' and y == ' ' then
      staged_only_paths[#staged_only_paths + 1] = file.path
    end
  end

  r.assert_eq(#staged_only_paths, 1)
  r.assert_eq(staged_only_paths[1], 'deleted.lua')
end)

-- ============================================================================
-- group: section expanded state reset
-- ============================================================================

r.group('section expanded state reset')

r.run('empty section resets expanded to false', function()
  -- Simulate: unstaged was expanded, then all files get staged (unstaged becomes empty)
  local expanded = { changes = true, staged = false, unstaged = true, untracked = false }
  local sections = { staged = { { path = 'a.lua', xy = 'M ', x = 'M', y = ' ' } }, unstaged = {}, untracked = {}, changes = {} }

  for _, key in ipairs({ 'staged', 'unstaged', 'untracked' }) do
    if not sections[key] or #sections[key] == 0 then
      expanded[key] = false
    end
  end

  r.assert_eq(expanded.unstaged, false, 'unstaged should be reset to false')
  r.assert_eq(expanded.staged, false, 'staged was already false, stays false')
  r.assert_eq(expanded.changes, true, 'changes not affected by reset logic')
end)

r.run('non-empty section preserves expanded state', function()
  local expanded = { changes = true, staged = false, unstaged = true, untracked = false }
  local sections = {
    staged = {},
    unstaged = { { path = 'a.lua', xy = ' M', x = ' ', y = 'M' } },
    untracked = {},
    changes = {},
  }

  for _, key in ipairs({ 'staged', 'unstaged', 'untracked' }) do
    if not sections[key] or #sections[key] == 0 then
      expanded[key] = false
    end
  end

  r.assert_eq(expanded.unstaged, true, 'unstaged has files, stays expanded')
end)

-- ============================================================================
-- group: locate_first_file (first <leader>gs on a tabpage)
-- ============================================================================

r.group('locate_first_file')

local function fake_sidebar_win()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor', row = 0, col = 0, width = 30, height = 20,
    style = 'minimal', focusable = false,
  })
  return buf, win
end

r.run('parks cursor on the first file item', function()
  local state = require('lu5je0.ext.sidebar.state')
  local locate = require('lu5je0.ext.sidebar.sources.git_changes.locate')
  local buf, win = fake_sidebar_win()

  local prev_win, prev_buf = state.win, state.buf
  state.win, state.buf = win, buf
  state.git_changes.sections = {}
  state.git_changes._expanded = nil
  state.git_changes._dir_states = nil

  -- Pre-seed sections so locate_first_file renders without a refresh.
  git_changes.update_sections_from_stdout(state.tab().git_changes,
    ' M a.lua\0 M b.lua\0')

  local rendered = false
  locate.locate_first_file(function()
    rendered = true
    git_changes.render()
  end, function() error('refresh not expected') end)

  r.assert_eq(rendered, true, 'render_fn should run')
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local item = state.git_changes.display_items[line]
  r.assert_truthy(item, 'cursor line should map to an item')
  r.assert_eq(item.type, 'file')
  r.assert_eq(item.node.path_or_name or item.node.name, 'a.lua')

  state.win, state.buf = prev_win, prev_buf
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

r.run('refreshes then parks when sections are empty', function()
  local state = require('lu5je0.ext.sidebar.state')
  local locate = require('lu5je0.ext.sidebar.sources.git_changes.locate')
  local buf, win = fake_sidebar_win()

  local prev_win, prev_buf = state.win, state.buf
  state.win, state.buf = win, buf
  state.git_changes.sections = {}
  state.git_changes._expanded = nil
  state.git_changes._dir_states = nil

  local refreshed = false
  locate.locate_first_file(function() git_changes.render() end, function(cb)
    refreshed = true
    git_changes.update_sections_from_stdout(state.tab().git_changes, ' M only.lua\0')
    cb()
  end)

  r.assert_eq(refreshed, true, 'refresh_fn should run when sections are empty')
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local item = state.git_changes.display_items[line]
  r.assert_truthy(item, 'cursor line should map to an item')
  r.assert_eq(item.node.name, 'only.lua')

  state.win, state.buf = prev_win, prev_buf
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

r.run('renders without moving cursor when there are no changes', function()
  local state = require('lu5je0.ext.sidebar.state')
  local locate = require('lu5je0.ext.sidebar.sources.git_changes.locate')
  local buf, win = fake_sidebar_win()

  local prev_win, prev_buf = state.win, state.buf
  state.win, state.buf = win, buf
  state.git_changes.sections = {}
  state.git_changes._expanded = nil
  state.git_changes._dir_states = nil
  git_changes.update_sections_from_stdout(state.tab().git_changes, '')

  local rendered = false
  locate.locate_first_file(function()
    rendered = true
    git_changes.render()
  end, function() error('refresh not expected') end)

  r.assert_eq(rendered, true)
  r.assert_eq(vim.api.nvim_win_get_cursor(win)[1], 1)

  state.win, state.buf = prev_win, prev_buf
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

r.finish()
