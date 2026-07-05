-- Sidebar tests: pure logic units that don't require an open sidebar window.
-- Usage: cd vim && nvim --headless -u NONE -l tests/sidebar/spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local files = require('lu5je0.ext.sidebar.sources.files')
local render = require('lu5je0.ext.sidebar.render')
local config = require('lu5je0.ext.sidebar.config')

-- ============================================================================
-- group: git status parsing
-- ============================================================================

r.group('git status parsing')

r.run('untracked file produces SidebarGitNew', function()
  local map = files._build_git_status_map('?? new.txt\0')
  r.assert_eq(map['new.txt'].xy, '??')
  r.assert_eq(map['new.txt'].hl, 'SidebarGitNew')
  r.assert_eq(map['new.txt'].glyph, config.files.git_glyphs.untracked)
end)

r.run('staged add produces SidebarGitStaged', function()
  local map = files._build_git_status_map('A  staged.txt\0')
  r.assert_eq(map['staged.txt'].hl, 'SidebarGitStaged')
end)

r.run('unstaged modification produces SidebarGitDirty', function()
  local map = files._build_git_status_map(' M dirty.txt\0')
  r.assert_eq(map['dirty.txt'].hl, 'SidebarGitDirty')
end)

r.run('rename consumes the next NUL entry as old path', function()
  -- `git status -z` for renames emits: "R  new\0old\0"
  local map = files._build_git_status_map('R  new.txt\0old.txt\0?? other.txt\0')
  r.assert_eq(map['new.txt'].hl, 'SidebarGitDirty')
  -- old.txt is the rename source, must NOT be parsed as its own entry
  r.assert_eq(map['old.txt'], nil)
  -- the next real entry continues to parse correctly
  r.assert_eq(map['other.txt'].hl, 'SidebarGitNew')
  -- and the parser must not have advanced into "old.txt" producing phantom keys
  local keys = {}
  for k in pairs(map) do keys[#keys + 1] = k end
  table.sort(keys)
  r.assert_eq(table.concat(keys, ','), 'new.txt,other.txt')
end)

r.run('directory aggregation picks highest priority among children', function()
  -- Dirty (priority 1) wins over New (2) wins over Staged (3)
  local map = files._build_git_status_map(table.concat({
    'A  pkg/staged.txt',
    '?? pkg/new.txt',
    ' M pkg/dirty.txt',
    '',
  }, '\0'))
  r.assert_eq(map['pkg/'].hl, 'SidebarGitDirty')
end)

r.run('directory aggregation excludes ignored files', function()
  local map = files._build_git_status_map(table.concat({
    '!! pkg/ignored.txt',
    'A  pkg/staged.txt',
    '',
  }, '\0'))
  r.assert_eq(map['pkg/'].hl, 'SidebarGitStaged')
end)

r.run('nested directories all receive the aggregated status', function()
  local map = files._build_git_status_map(' M a/b/c/file.txt\0')
  r.assert_eq(map['a/'].hl, 'SidebarGitDirty')
  r.assert_eq(map['a/b/'].hl, 'SidebarGitDirty')
  r.assert_eq(map['a/b/c/'].hl, 'SidebarGitDirty')
end)

r.run('empty stdout returns empty map', function()
  r.assert_eq(files._build_git_status_map(''), {})
  r.assert_eq(files._build_git_status_map(nil), {})
end)

-- ============================================================================
-- group: status code -> glyph mapping
-- ============================================================================

r.group('git status -> glyph')

r.run('!! ignored', function()
  local _, hl = files._git_status_to_glyph('!!')
  r.assert_eq(hl, 'SidebarGitIgnored')
end)

r.run('?? untracked', function()
  local _, hl = files._git_status_to_glyph('??')
  r.assert_eq(hl, 'SidebarGitNew')
end)

r.run('D in either column => deleted/dirty', function()
  local _, hl_x = files._git_status_to_glyph('D ')
  local _, hl_y = files._git_status_to_glyph(' D')
  r.assert_eq(hl_x, 'SidebarGitDirty')
  r.assert_eq(hl_y, 'SidebarGitDirty')
end)

r.run('R rename => dirty', function()
  local _, hl = files._git_status_to_glyph('R ')
  r.assert_eq(hl, 'SidebarGitDirty')
end)

r.run('A add => staged', function()
  local _, hl = files._git_status_to_glyph('A ')
  r.assert_eq(hl, 'SidebarGitStaged')
end)

r.run('MM staged-and-unstaged-modified => staged (X column wins)', function()
  local _, hl = files._git_status_to_glyph('MM')
  r.assert_eq(hl, 'SidebarGitStaged')
end)

r.run('" M" worktree-only modification => dirty', function()
  local _, hl = files._git_status_to_glyph(' M')
  r.assert_eq(hl, 'SidebarGitDirty')
end)

-- ============================================================================
-- group: render_tree engine
-- ============================================================================

r.group('render_tree')

local function file_node(name)
  return { name = name, type = 'file' }
end

local function dir_node(name, children, expanded)
  return {
    name = name,
    type = 'directory',
    children = children,
    expanded = expanded == nil and true or expanded,
  }
end

r.run('flat directory: collapsed dir hides its children, file rendered', function()
  local tree = {
    dir_node('pkg', { file_node('a.txt') }, false),
    file_node('top.txt'),
  }
  local lines, items = render.render_tree(tree, {})
  -- two visible lines: pkg (collapsed) and top.txt
  r.assert_eq(#lines, 2)
  r.assert_eq(items[1].type, 'dir')
  r.assert_eq(items[1].node.name, 'pkg')
  r.assert_eq(items[2].type, 'file')
  r.assert_eq(items[2].node.name, 'top.txt')
end)

r.run('expanded directory shows children with branch prefix', function()
  local tree = {
    dir_node('pkg', { file_node('a.txt'), file_node('b.txt') }, true),
  }
  local lines, items = render.render_tree(tree, {})
  r.assert_eq(#lines, 3)
  r.assert_eq(items[1].type, 'dir')
  r.assert_eq(items[2].node.name, 'a.txt')
  r.assert_eq(items[3].node.name, 'b.txt')
  -- last child uses └, non-last uses │
  if not lines[2]:find('│') then
    error('expected non-last child to use │ branch, got: ' .. lines[2])
  end
  if not lines[3]:find('└') then
    error('expected last child to use └ branch, got: ' .. lines[3])
  end
end)

r.run('filter hides dotfiles', function()
  local tree = {
    file_node('.hidden'),
    file_node('visible.txt'),
  }
  local lines, items = render.render_tree(tree, {
    filter = function(node) return not node.name:match('^%.') end,
  })
  r.assert_eq(#lines, 1)
  r.assert_eq(items[1].node.name, 'visible.txt')
end)

r.run('compress_dirs collapses single-child expanded chain into one line', function()
  -- a/b/c with each containing exactly one expanded subdir, leaf has a file
  local leaf = dir_node('c', { file_node('x.txt') }, true)
  local b = dir_node('b', { leaf }, true)
  local a = dir_node('a', { b }, true)
  local lines = render.render_tree({ a }, { compress_dirs = true })
  -- expected: line 1 'a/b/c', line 2 'x.txt'  → 2 lines total
  r.assert_eq(#lines, 2)
  if not lines[1]:find('a/b/c') then
    error('expected compressed name "a/b/c", got: ' .. lines[1])
  end
end)

r.run('compress_dirs stops when a level has multiple visible children', function()
  local leaf = dir_node('c', { file_node('x.txt'), file_node('y.txt') }, true)
  local b = dir_node('b', { leaf }, true)
  local a = dir_node('a', { b }, true)
  local lines = render.render_tree({ a }, { compress_dirs = true })
  -- 'a/b/c' compressed, then x.txt and y.txt as children → 3 lines
  r.assert_eq(#lines, 3)
  if not lines[1]:find('a/b/c') then
    error('expected compressed name "a/b/c", got: ' .. lines[1])
  end
end)

r.run('file_suffix produces a virt_text entry', function()
  local tree = { file_node('a.txt') }
  local _, _, _, virt_texts = render.render_tree(tree, {
    file_suffix = function(_) return 'M', 'SidebarGitDirty' end,
  })
  r.assert_eq(#virt_texts, 1)
  r.assert_eq(virt_texts[1].line, 0)
  r.assert_eq(virt_texts[1].virt_text, { { 'M', 'SidebarGitDirty' } })
end)

r.run('item_data fields are merged into items', function()
  local tree = { file_node('a.txt') }
  local _, items = render.render_tree(tree, {
    item_data = function(_) return { extra = 42 } end,
  })
  r.assert_eq(items[1].extra, 42)
end)

-- ============================================================================
-- group: live_filter (make_filter with state.files.live_filter)
-- ============================================================================

r.group('live_filter')

local state = require('lu5je0.ext.sidebar.state')
local tree_mod = require('lu5je0.ext.sidebar.sources.files.tree')

r.run('live_filter hides non-matching files', function()
  state.files.live_filter = 'lua'
  state.files.hide_dotfiles = false
  local filter = tree_mod.make_filter(nil)
  r.assert_eq(filter(file_node('init.lua')), true)
  r.assert_eq(filter(file_node('readme.md')), false)
  state.files.live_filter = nil
end)

r.run('live_filter directories are never filtered', function()
  state.files.live_filter = 'lua'
  state.files.hide_dotfiles = false
  local filter = tree_mod.make_filter(nil)
  local dir = dir_node('src', { file_node('readme.md') }, true)
  r.assert_eq(filter(dir), true)
  state.files.live_filter = nil
end)

r.run('live_filter is case-insensitive', function()
  state.files.live_filter = 'LUA'
  state.files.hide_dotfiles = false
  local filter = tree_mod.make_filter(nil)
  r.assert_eq(filter(file_node('init.lua')), true)
  r.assert_eq(filter(file_node('Init.LUA')), true)
  state.files.live_filter = nil
end)

r.run('live_filter supports regex patterns', function()
  state.files.live_filter = '\\.lua$'
  state.files.hide_dotfiles = false
  local filter = tree_mod.make_filter(nil)
  r.assert_eq(filter(file_node('init.lua')), true)
  r.assert_eq(filter(file_node('lua_stuff.txt')), false)
  state.files.live_filter = nil
end)

r.run('live_filter supports Perl-style lazy quantifiers', function()
  state.files.live_filter = 'i.*?t'
  state.files.hide_dotfiles = false
  local filter = tree_mod.make_filter(nil)
  r.assert_eq(filter(file_node('init.lua')), true)
  r.assert_eq(filter(file_node('test.txt')), false)
  state.files.live_filter = nil
end)

r.run('live_filter invalid regex does not crash', function()
  state.files.live_filter = '[invalid'
  state.files.hide_dotfiles = false
  local filter = tree_mod.make_filter(nil)
  -- invalid regex means regex is nil, nothing is filtered
  r.assert_eq(filter(file_node('anything.txt')), true)
  state.files.live_filter = nil
end)

r.run('live_filter empty string does not filter', function()
  state.files.live_filter = ''
  state.files.hide_dotfiles = false
  local filter = tree_mod.make_filter(nil)
  r.assert_eq(filter(file_node('anything.txt')), true)
  state.files.live_filter = nil
end)

r.run('live_filter combined with dotfile hiding', function()
  state.files.live_filter = 'rc'
  state.files.hide_dotfiles = true
  local filter = tree_mod.make_filter(nil)
  r.assert_eq(filter({ name = '.bashrc', type = 'file', abs_path = '/home/.bashrc' }), false)
  r.assert_eq(filter({ name = 'vimrc', type = 'file', abs_path = '/home/vimrc' }), true)
  r.assert_eq(filter({ name = 'readme.md', type = 'file', abs_path = '/home/readme.md' }), false)
  state.files.live_filter = nil
end)

-- ============================================================================
-- summary
-- ============================================================================

r.finish()
