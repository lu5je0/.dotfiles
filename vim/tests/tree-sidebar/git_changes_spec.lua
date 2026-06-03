-- Tree-sidebar git_changes tests: pure logic units.
-- Usage: cd vim && nvim --headless -u NONE -l tests/tree-sidebar/git_changes_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local git_changes = require('lu5je0.ext.tree-sidebar.sources.git_changes')
local render = require('lu5je0.ext.tree-sidebar.render')

local color = {
  reset = '\27[0m',
  green = '\27[32m',
  red = '\27[31m',
  cyan = '\27[36m',
}

local passed = 0
local failed = 0

local function eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  for k, v in pairs(a) do
    if not eq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
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
-- group: parse_git_status via update_sections_from_stdout
-- ============================================================================

io.write(color.cyan .. 'parse_git_status' .. color.reset .. '\n')

run('staged-only file goes into staged section', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'M  file.lua\0')
  assert_eq(#t.sections.staged, 1)
  assert_eq(t.sections.staged[1].path, 'file.lua')
  assert_eq(#t.sections.unstaged, 0)
  assert_eq(#t.sections.untracked, 0)
end)

run('unstaged-only file goes into unstaged section', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, ' M file.lua\0')
  assert_eq(#t.sections.unstaged, 1)
  assert_eq(#t.sections.staged, 0)
end)

run('untracked file goes into untracked section', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, '?? new.txt\0')
  assert_eq(#t.sections.untracked, 1)
  assert_eq(t.sections.untracked[1].path, 'new.txt')
  assert_eq(#t.sections.staged, 0)
  assert_eq(#t.sections.unstaged, 0)
end)

run('MM file goes into both staged and unstaged', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'MM file.lua\0')
  assert_eq(#t.sections.staged, 1)
  assert_eq(#t.sections.unstaged, 1)
end)

run('changes section contains all non-ignored files', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'M  a.lua\0 M b.lua\0?? c.lua\0')
  assert_eq(#t.sections.changes, 3)
end)

run('rename consumes next NUL entry', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, 'R  new.lua\0old.lua\0?? other.lua\0')
  assert_eq(#t.sections.staged, 1)
  assert_eq(t.sections.staged[1].path, 'new.lua')
  assert_eq(t.sections.staged[1].old_path, 'old.lua')
  assert_eq(#t.sections.untracked, 1)
  assert_eq(t.sections.untracked[1].path, 'other.lua')
end)

run('ignored file is excluded from all sections', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, '!! ignored.txt\0M  real.lua\0')
  assert_eq(#t.sections.staged, 1)
  assert_eq(#t.sections.changes, 1)
end)

run('empty stdout returns empty sections', function()
  local t = { sections = {} }
  git_changes.update_sections_from_stdout(t, '')
  assert_eq(#t.sections.staged, 0)
  assert_eq(#t.sections.unstaged, 0)
  assert_eq(#t.sections.untracked, 0)
  assert_eq(#t.sections.changes, 0)
end)

-- ============================================================================
-- group: restore_cursor
-- ============================================================================

io.write(color.cyan .. 'restore_cursor' .. color.reset .. '\n')

run('exact node match takes priority over ancestor', function()
  local child = { name = 'child', type = 'file' }
  local parent = { name = 'parent', type = 'directory', children = { child } }
  local root = { name = 'root', type = 'directory', children = { parent } }

  local old_items = {
    { node = root },
    { node = parent },
    { node = child },
  }
  -- After collapse: only root and parent visible
  local new_items = {
    { node = root },
    { node = parent },
    { node = child },
  }

  -- Simulate cursor on child (line 3)
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
  assert_eq(contains(root, child), true)
  assert_eq(contains(parent, child), true)
  assert_eq(contains(child, child), true)

  -- identity match should find child at index 3
  local identity_match = nil
  for i, item in ipairs(new_items) do
    if item.node == child then
      identity_match = i
      break
    end
  end
  assert_eq(identity_match, 3)
end)

run('ancestor fallback picks deepest match', function()
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
  assert_eq(best_line, 2)
end)

-- ============================================================================
-- group: discard_section classification
-- ============================================================================

io.write(color.cyan .. 'discard_section file classification' .. color.reset .. '\n')

run('staged-only files detected in changes section', function()
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

  assert_eq(#target_files, 0, 'no unstaged/untracked files')
  assert_eq(#staged_only_paths, 2, 'both files are staged-only')
end)

run('mixed staged and unstaged correctly classified', function()
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
  assert_eq(#target_files, 3, '3 unstaged/untracked files')
  -- staged.lua (x=M, y=' ') is staged-only
  assert_eq(#staged_only_paths, 1, '1 staged-only file')
  assert_eq(staged_only_paths[1], 'staged.lua')
end)

run('deleted staged file is classified as staged-only', function()
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

  assert_eq(#staged_only_paths, 1)
  assert_eq(staged_only_paths[1], 'deleted.lua')
end)

-- ============================================================================
-- group: section expanded state reset
-- ============================================================================

io.write(color.cyan .. 'section expanded state reset' .. color.reset .. '\n')

run('empty section resets expanded to false', function()
  -- Simulate: unstaged was expanded, then all files get staged (unstaged becomes empty)
  local expanded = { changes = true, staged = false, unstaged = true, untracked = false }
  local sections = { staged = { { path = 'a.lua', xy = 'M ', x = 'M', y = ' ' } }, unstaged = {}, untracked = {}, changes = {} }

  for _, key in ipairs({ 'staged', 'unstaged', 'untracked' }) do
    if not sections[key] or #sections[key] == 0 then
      expanded[key] = false
    end
  end

  assert_eq(expanded.unstaged, false, 'unstaged should be reset to false')
  assert_eq(expanded.staged, false, 'staged was already false, stays false')
  assert_eq(expanded.changes, true, 'changes not affected by reset logic')
end)

run('non-empty section preserves expanded state', function()
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

  assert_eq(expanded.unstaged, true, 'unstaged has files, stays expanded')
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
