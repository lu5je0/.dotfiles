-- Tree-sidebar tests: pure logic units that don't require an open sidebar window.
-- Usage: cd vim && nvim --headless -u NONE -l tests/tree-sidebar/spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local files = require('lu5je0.ext.tree-sidebar.sources.files')
local render = require('lu5je0.ext.tree-sidebar.render')
local config = require('lu5je0.ext.tree-sidebar.config')

local color = {
  reset = '\27[0m',
  green = '\27[32m',
  red = '\27[31m',
  cyan = '\27[36m',
}

local passed = 0
local failed = 0

local function eq(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= 'table' then
    return a == b
  end
  for k, v in pairs(a) do
    if not eq(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function dump(v, depth)
  depth = depth or 0
  if depth > 4 then return '...' end
  if type(v) ~= 'table' then return tostring(v) end
  local parts = {}
  for k, val in pairs(v) do
    parts[#parts + 1] = string.format('%s=%s', tostring(k), dump(val, depth + 1))
  end
  table.sort(parts)
  return '{' .. table.concat(parts, ', ') .. '}'
end

local function run(name, fn)
  io.write(string.format('  %s ... ', name))
  local ok, err = pcall(fn)
  if ok then
    io.write(color.green .. 'PASS' .. color.reset .. '\n')
    passed = passed + 1
  else
    io.write(color.red .. 'FAIL' .. color.reset .. '\n    ' .. tostring(err) .. '\n')
    failed = failed + 1
  end
end

local function assert_eq(actual, expected, msg)
  if not eq(actual, expected) then
    error(string.format('%s\n      actual:   %s\n      expected: %s',
      msg or 'assertion failed', dump(actual), dump(expected)), 2)
  end
end

-- ============================================================================
-- group: git status parsing
-- ============================================================================

io.write(color.cyan .. 'git status parsing' .. color.reset .. '\n')

run('untracked file produces TreeSidebarGitNew', function()
  local map = files._build_git_status_map('?? new.txt\0')
  assert_eq(map['new.txt'].xy, '??')
  assert_eq(map['new.txt'].hl, 'TreeSidebarGitNew')
  assert_eq(map['new.txt'].glyph, config.git_glyphs.untracked)
end)

run('staged add produces TreeSidebarGitStaged', function()
  local map = files._build_git_status_map('A  staged.txt\0')
  assert_eq(map['staged.txt'].hl, 'TreeSidebarGitStaged')
end)

run('unstaged modification produces TreeSidebarGitDirty', function()
  local map = files._build_git_status_map(' M dirty.txt\0')
  assert_eq(map['dirty.txt'].hl, 'TreeSidebarGitDirty')
end)

run('rename consumes the next NUL entry as old path', function()
  -- `git status -z` for renames emits: "R  new\0old\0"
  local map = files._build_git_status_map('R  new.txt\0old.txt\0?? other.txt\0')
  assert_eq(map['new.txt'].hl, 'TreeSidebarGitDirty')
  -- old.txt is the rename source, must NOT be parsed as its own entry
  assert_eq(map['old.txt'], nil)
  -- the next real entry continues to parse correctly
  assert_eq(map['other.txt'].hl, 'TreeSidebarGitNew')
  -- and the parser must not have advanced into "old.txt" producing phantom keys
  local keys = {}
  for k in pairs(map) do keys[#keys + 1] = k end
  table.sort(keys)
  assert_eq(table.concat(keys, ','), 'new.txt,other.txt')
end)

run('directory aggregation picks highest priority among children', function()
  -- Dirty (priority 1) wins over New (2) wins over Staged (3)
  local map = files._build_git_status_map(table.concat({
    'A  pkg/staged.txt',
    '?? pkg/new.txt',
    ' M pkg/dirty.txt',
    '',
  }, '\0'))
  assert_eq(map['pkg/'].hl, 'TreeSidebarGitDirty')
end)

run('directory aggregation excludes ignored files', function()
  local map = files._build_git_status_map(table.concat({
    '!! pkg/ignored.txt',
    'A  pkg/staged.txt',
    '',
  }, '\0'))
  assert_eq(map['pkg/'].hl, 'TreeSidebarGitStaged')
end)

run('nested directories all receive the aggregated status', function()
  local map = files._build_git_status_map(' M a/b/c/file.txt\0')
  assert_eq(map['a/'].hl, 'TreeSidebarGitDirty')
  assert_eq(map['a/b/'].hl, 'TreeSidebarGitDirty')
  assert_eq(map['a/b/c/'].hl, 'TreeSidebarGitDirty')
end)

run('empty stdout returns empty map', function()
  assert_eq(files._build_git_status_map(''), {})
  assert_eq(files._build_git_status_map(nil), {})
end)

-- ============================================================================
-- group: status code -> glyph mapping
-- ============================================================================

io.write(color.cyan .. 'git status -> glyph' .. color.reset .. '\n')

run('!! ignored', function()
  local _, hl = files._git_status_to_glyph('!!')
  assert_eq(hl, 'TreeSidebarGitIgnored')
end)

run('?? untracked', function()
  local _, hl = files._git_status_to_glyph('??')
  assert_eq(hl, 'TreeSidebarGitNew')
end)

run('D in either column => deleted/dirty', function()
  local _, hl_x = files._git_status_to_glyph('D ')
  local _, hl_y = files._git_status_to_glyph(' D')
  assert_eq(hl_x, 'TreeSidebarGitDirty')
  assert_eq(hl_y, 'TreeSidebarGitDirty')
end)

run('R rename => dirty', function()
  local _, hl = files._git_status_to_glyph('R ')
  assert_eq(hl, 'TreeSidebarGitDirty')
end)

run('A add => staged', function()
  local _, hl = files._git_status_to_glyph('A ')
  assert_eq(hl, 'TreeSidebarGitStaged')
end)

run('MM staged-and-unstaged-modified => staged (X column wins)', function()
  local _, hl = files._git_status_to_glyph('MM')
  assert_eq(hl, 'TreeSidebarGitStaged')
end)

run('" M" worktree-only modification => dirty', function()
  local _, hl = files._git_status_to_glyph(' M')
  assert_eq(hl, 'TreeSidebarGitDirty')
end)

-- ============================================================================
-- group: render_tree engine
-- ============================================================================

io.write(color.cyan .. 'render_tree' .. color.reset .. '\n')

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

run('flat directory: collapsed dir hides its children, file rendered', function()
  local tree = {
    dir_node('pkg', { file_node('a.txt') }, false),
    file_node('top.txt'),
  }
  local lines, items = render.render_tree(tree, {})
  -- two visible lines: pkg (collapsed) and top.txt
  assert_eq(#lines, 2)
  assert_eq(items[1].type, 'dir')
  assert_eq(items[1].node.name, 'pkg')
  assert_eq(items[2].type, 'file')
  assert_eq(items[2].node.name, 'top.txt')
end)

run('expanded directory shows children with branch prefix', function()
  local tree = {
    dir_node('pkg', { file_node('a.txt'), file_node('b.txt') }, true),
  }
  local lines, items = render.render_tree(tree, {})
  assert_eq(#lines, 3)
  assert_eq(items[1].type, 'dir')
  assert_eq(items[2].node.name, 'a.txt')
  assert_eq(items[3].node.name, 'b.txt')
  -- last child uses └, non-last uses │
  if not lines[2]:find('│') then
    error('expected non-last child to use │ branch, got: ' .. lines[2])
  end
  if not lines[3]:find('└') then
    error('expected last child to use └ branch, got: ' .. lines[3])
  end
end)

run('filter hides dotfiles', function()
  local tree = {
    file_node('.hidden'),
    file_node('visible.txt'),
  }
  local lines, items = render.render_tree(tree, {
    filter = function(node) return not node.name:match('^%.') end,
  })
  assert_eq(#lines, 1)
  assert_eq(items[1].node.name, 'visible.txt')
end)

run('compress_dirs collapses single-child expanded chain into one line', function()
  -- a/b/c with each containing exactly one expanded subdir, leaf has a file
  local leaf = dir_node('c', { file_node('x.txt') }, true)
  local b = dir_node('b', { leaf }, true)
  local a = dir_node('a', { b }, true)
  local lines = render.render_tree({ a }, { compress_dirs = true })
  -- expected: line 1 'a/b/c', line 2 'x.txt'  → 2 lines total
  assert_eq(#lines, 2)
  if not lines[1]:find('a/b/c') then
    error('expected compressed name "a/b/c", got: ' .. lines[1])
  end
end)

run('compress_dirs stops when a level has multiple visible children', function()
  local leaf = dir_node('c', { file_node('x.txt'), file_node('y.txt') }, true)
  local b = dir_node('b', { leaf }, true)
  local a = dir_node('a', { b }, true)
  local lines = render.render_tree({ a }, { compress_dirs = true })
  -- 'a/b/c' compressed, then x.txt and y.txt as children → 3 lines
  assert_eq(#lines, 3)
  if not lines[1]:find('a/b/c') then
    error('expected compressed name "a/b/c", got: ' .. lines[1])
  end
end)

run('file_suffix produces a virt_text entry', function()
  local tree = { file_node('a.txt') }
  local _, _, _, virt_texts = render.render_tree(tree, {
    file_suffix = function(_) return 'M', 'TreeSidebarGitDirty' end,
  })
  assert_eq(#virt_texts, 1)
  assert_eq(virt_texts[1].line, 0)
  assert_eq(virt_texts[1].virt_text, { { 'M', 'TreeSidebarGitDirty' } })
end)

run('item_data fields are merged into items', function()
  local tree = { file_node('a.txt') }
  local _, items = render.render_tree(tree, {
    item_data = function(_) return { extra = 42 } end,
  })
  assert_eq(items[1].extra, 42)
end)

-- ============================================================================
-- summary
-- ============================================================================

io.write(string.format('\n%s passed, %s failed\n',
  color.green .. tostring(passed) .. color.reset,
  (failed > 0 and color.red or color.green) .. tostring(failed) .. color.reset))

if failed > 0 then
  os.exit(1)
end
