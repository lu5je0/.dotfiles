-- diff_preview tests: pure resolve_diff_targets mapping.
-- Usage: cd vim && nvim --headless -u NONE -l tests/tree-sidebar/diff_preview_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local diff_preview = require('lu5je0.ext.tree-sidebar.actions.diff_preview')

local color = {
  reset = '\27[0m', green = '\27[32m', red = '\27[31m', cyan = '\27[36m',
}
local passed, failed = 0, 0

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

local function assert_eq(actual, expected, msg)
  local function eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  end
  if not eq(actual, expected) then
    error(string.format('%s\n      actual:   %s\n      expected: %s',
      msg or 'mismatch', dump(actual), dump(expected)), 2)
  end
end

local function run(name, fn)
  io.write('  ' .. name .. ' ... ')
  local ok, err = pcall(fn)
  if ok then
    io.write(color.green .. 'PASS' .. color.reset .. '\n')
    passed = passed + 1
  else
    io.write(color.red .. 'FAIL' .. color.reset .. '\n    ' .. tostring(err) .. '\n')
    failed = failed + 1
  end
end

-- ============================================================================
-- Build a synthetic display item like git_changes.lua's render produces.
-- ============================================================================

local function make_item(section, xy, rel_path)
  local cwd = vim.fn.getcwd()
  return {
    type = 'file',
    section = section,
    xy = xy,
    path = rel_path,
    node = {
      type = 'file',
      name = rel_path:match('([^/]+)$'),
      rel_path = rel_path,
      abs_path = cwd .. '/' .. rel_path,
      xy = xy,
      section = section,
    },
  }
end

io.write(color.cyan .. 'resolve_diff_targets' .. color.reset .. '\n')

run('staged section: HEAD vs Index', function()
  local t = diff_preview.resolve_diff_targets(make_item('staged', 'M ', 'foo.txt'))
  assert_eq(t.left, { kind = 'git_show', spec = 'HEAD:foo.txt' })
  assert_eq(t.right, { kind = 'git_show', spec = ':foo.txt' })
  assert_eq(t.left_title, ' HEAD ')
  assert_eq(t.right_title, ' Index ')
end)

run('unstaged section: Index vs Working Tree', function()
  local item = make_item('unstaged', ' M', 'foo.txt')
  local t = diff_preview.resolve_diff_targets(item)
  assert_eq(t.left, { kind = 'git_show', spec = ':foo.txt' })
  assert_eq(t.right.kind, 'worktree')
  assert_eq(t.right.path, item.node.abs_path)
  assert_eq(t.left_title, ' Index ')
  assert_eq(t.right_title, ' Working Tree ')
end)

run('untracked section: empty vs Working Tree', function()
  local item = make_item('untracked', '??', 'new.txt')
  local t = diff_preview.resolve_diff_targets(item)
  assert_eq(t.left, { kind = 'empty' })
  assert_eq(t.right.kind, 'worktree')
end)

run('xy=?? falls back to untracked behaviour even without explicit section', function()
  local item = make_item(nil, '??', 'new.txt')
  local t = diff_preview.resolve_diff_targets(item)
  assert_eq(t.left.kind, 'empty')
  assert_eq(t.right.kind, 'worktree')
end)

run('changes (combined) section: HEAD vs Working Tree', function()
  local item = make_item('changes', 'MM', 'foo.txt')
  local t = diff_preview.resolve_diff_targets(item)
  assert_eq(t.left.spec, 'HEAD:foo.txt')
  assert_eq(t.right.kind, 'worktree')
  assert_eq(t.left_title, ' HEAD ')
  assert_eq(t.right_title, ' Working Tree ')
end)

run('MM file: staged section diffs HEAD↔Index, unstaged section diffs Index↔WT', function()
  local staged_item = make_item('staged', 'MM', 'mm.txt')
  local unstaged_item = make_item('unstaged', 'MM', 'mm.txt')
  local s = diff_preview.resolve_diff_targets(staged_item)
  local u = diff_preview.resolve_diff_targets(unstaged_item)
  assert_eq(s.left.spec, 'HEAD:mm.txt')
  assert_eq(s.right.spec, ':mm.txt')
  assert_eq(u.left.spec, ':mm.txt')
  assert_eq(u.right.kind, 'worktree')
end)

run('rel_path falls back from abs_path when node.rel_path missing', function()
  local cwd = vim.fn.getcwd()
  local item = {
    type = 'file',
    section = 'staged',
    xy = 'M ',
    node = {
      type = 'file',
      name = 'bar.txt',
      abs_path = cwd .. '/dir/bar.txt',
      xy = 'M ',
      section = 'staged',
    },
  }
  local t = diff_preview.resolve_diff_targets(item)
  assert_eq(t.left.spec, 'HEAD:dir/bar.txt')
  assert_eq(t.right.spec, ':dir/bar.txt')
end)

run('unknown section falls through to HEAD vs Working Tree', function()
  local item = make_item('mystery', 'M ', 'foo.txt')
  local t = diff_preview.resolve_diff_targets(item)
  assert_eq(t.left.spec, 'HEAD:foo.txt')
  assert_eq(t.right.kind, 'worktree')
end)

io.write(string.format('\n%s passed, %s failed\n',
  color.green .. tostring(passed) .. color.reset,
  (failed > 0 and color.red or color.green) .. tostring(failed) .. color.reset))

if failed > 0 then os.exit(1) end
