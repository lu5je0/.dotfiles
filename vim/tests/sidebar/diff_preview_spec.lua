-- diff_preview tests: pure resolve_diff_targets mapping.
-- Usage: cd vim && nvim --headless -u NONE -l tests/sidebar/diff_preview_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local diff_preview = require('lu5je0.ext.sidebar.actions.diff_preview')

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

r.group('resolve_diff_targets')

r.run('staged section: HEAD vs Index', function()
  local t = diff_preview.resolve_diff_targets(make_item('staged', 'M ', 'foo.txt'))
  r.assert_eq(t.left, { kind = 'git_show', spec = 'HEAD:foo.txt' })
  r.assert_eq(t.right, { kind = 'git_show', spec = ':foo.txt' })
  r.assert_eq(t.left_title, ' HEAD ')
  r.assert_eq(t.right_title, ' Index ')
end)

r.run('unstaged section: Index vs Working Tree', function()
  local item = make_item('unstaged', ' M', 'foo.txt')
  local t = diff_preview.resolve_diff_targets(item)
  r.assert_eq(t.left, { kind = 'git_show', spec = ':foo.txt' })
  r.assert_eq(t.right.kind, 'worktree')
  r.assert_eq(t.right.path, item.node.abs_path)
  r.assert_eq(t.left_title, ' Index ')
  r.assert_eq(t.right_title, ' Working Tree ')
end)

r.run('untracked section: empty vs Working Tree', function()
  local item = make_item('untracked', '??', 'new.txt')
  local t = diff_preview.resolve_diff_targets(item)
  r.assert_eq(t.left, { kind = 'empty' })
  r.assert_eq(t.right.kind, 'worktree')
end)

r.run('xy=?? falls back to untracked behaviour even without explicit section', function()
  local item = make_item(nil, '??', 'new.txt')
  local t = diff_preview.resolve_diff_targets(item)
  r.assert_eq(t.left.kind, 'empty')
  r.assert_eq(t.right.kind, 'worktree')
end)

r.run('changes (combined) section: HEAD vs Working Tree', function()
  local item = make_item('changes', 'MM', 'foo.txt')
  local t = diff_preview.resolve_diff_targets(item)
  r.assert_eq(t.left.spec, 'HEAD:foo.txt')
  r.assert_eq(t.right.kind, 'worktree')
  r.assert_eq(t.left_title, ' HEAD ')
  r.assert_eq(t.right_title, ' Working Tree ')
end)

r.run('MM file: staged section diffs HEAD↔Index, unstaged section diffs Index↔WT', function()
  local staged_item = make_item('staged', 'MM', 'mm.txt')
  local unstaged_item = make_item('unstaged', 'MM', 'mm.txt')
  local s = diff_preview.resolve_diff_targets(staged_item)
  local u = diff_preview.resolve_diff_targets(unstaged_item)
  r.assert_eq(s.left.spec, 'HEAD:mm.txt')
  r.assert_eq(s.right.spec, ':mm.txt')
  r.assert_eq(u.left.spec, ':mm.txt')
  r.assert_eq(u.right.kind, 'worktree')
end)

r.run('rel_path falls back from abs_path when node.rel_path missing', function()
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
  r.assert_eq(t.left.spec, 'HEAD:dir/bar.txt')
  r.assert_eq(t.right.spec, ':dir/bar.txt')
end)

r.run('unknown section falls through to HEAD vs Working Tree', function()
  local item = make_item('mystery', 'M ', 'foo.txt')
  local t = diff_preview.resolve_diff_targets(item)
  r.assert_eq(t.left.spec, 'HEAD:foo.txt')
  r.assert_eq(t.right.kind, 'worktree')
end)

r.finish()
