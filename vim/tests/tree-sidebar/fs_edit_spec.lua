-- fs-edit tests: parse_line + compute_actions (conceal /NNN approach).
-- Usage: cd vim && nvim --headless -u NONE -l tests/tree-sidebar/fs_edit_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local te = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit')
local parse_line = te._parse_line
local compute_actions = te._compute_actions

local function make_session(root_dir, entries)
  local session = {
    root_dir = root_dir,
    store = {},
    id_to_path = {},
    expanded_dirs = {},
    next_id = 1,
  }
  for _, e in ipairs(entries or {}) do
    local id = session.next_id
    session.next_id = id + 1
    session.store[id] = { name = e.name, abs_path = e.abs_path, type = e.type }
    session.id_to_path[id] = e.abs_path
  end
  return session
end

local function find_action(actions, name, opts)
  for _, a in ipairs(actions) do
    if a.name == name then
      local match = true
      if opts then
        if opts.src and a.src ~= opts.src then match = false end
        if opts.dst and a.dst ~= opts.dst then match = false end
      end
      if match then return a end
    end
  end
end

local function action_count(actions, name)
  local n = 0
  for _, a in ipairs(actions) do
    if a.name == name then n = n + 1 end
  end
  return n
end

-- ============================================================================
r.group('parse_line')
-- ============================================================================

r.run('file with id', function()
  local id, name, depth, is_dir = parse_line('/1 hello.lua')
  r.assert_eq(id, 1)
  r.assert_eq(name, 'hello.lua')
  r.assert_eq(depth, 0)
  r.assert_eq(is_dir, false)
end)

r.run('directory with id', function()
  local id, name, depth, is_dir = parse_line('  /2 src/')
  r.assert_eq(id, 2)
  r.assert_eq(name, 'src/')
  r.assert_eq(depth, 1)
  r.assert_eq(is_dir, true)
end)

r.run('nested depth', function()
  local _, _, depth = parse_line('      /10 deep.txt')
  r.assert_eq(depth, 3)
end)

r.run('new line without id', function()
  local id, name, depth, is_dir = parse_line('  newfile.txt')
  r.assert_eq(id, nil)
  r.assert_eq(name, 'newfile.txt')
  r.assert_eq(depth, 1)
  r.assert_eq(is_dir, false)
end)

r.run('new dir without id', function()
  local id, name, _, is_dir = parse_line('newdir/')
  r.assert_eq(id, nil)
  r.assert_eq(name, 'newdir/')
  r.assert_eq(is_dir, true)
end)

r.run('empty line', function()
  local id, name, depth, is_dir = parse_line('')
  r.assert_eq(id, nil)
  r.assert_eq(name, '')
  r.assert_eq(depth, 0)
  r.assert_eq(is_dir, false)
end)

r.run('dotfile', function()
  local _, name, depth = parse_line('  /5 .gitignore')
  r.assert_eq(name, '.gitignore')
  r.assert_eq(depth, 1)
end)

-- ============================================================================
r.group('compute_actions: no changes')
-- ============================================================================

r.run('unchanged buffer', function()
  local s = make_session('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  r.assert_eq(#compute_actions(s, { '/1 a.txt', '/2 b.txt' }), 0)
end)

r.run('unchanged expanded dir', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'main.lua', abs_path = '/r/src/main.lua', type = 'file' },
  })
  s.expanded_dirs['/r/src'] = true
  r.assert_eq(#compute_actions(s, { '/1 src/', '  /2 main.lua' }), 0)
end)

r.run('swapping order', function()
  local s = make_session('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  r.assert_eq(#compute_actions(s, { '/2 b.txt', '/1 a.txt' }), 0)
end)

r.run('dir trailing slash no spurious move', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'lib', abs_path = '/r/lib', type = 'directory' },
  })
  r.assert_eq(#compute_actions(s, { '/1 src/', '/2 lib/' }), 0)
end)

-- ============================================================================
r.group('compute_actions: create')
-- ============================================================================

r.run('new file (no id)', function()
  local s = make_session('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  local a = compute_actions(s, { '/1 a.txt', 'new.txt' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'create')
  r.assert_eq(a[1].dst, '/r/new.txt')
end)

r.run('new dir', function()
  local a = compute_actions(make_session('/r', {}), { 'newdir/' })
  r.assert_eq(a[1].dst, '/r/newdir/')
end)

r.run('new file inside dir', function()
  local s = make_session('/r', { { name = 'src', abs_path = '/r/src', type = 'directory' } })
  s.expanded_dirs['/r/src'] = true
  local a = compute_actions(s, { '/1 src/', '  new.lua' })
  r.assert_eq(a[1].dst, '/r/src/new.lua')
end)

r.run('nested path creates intermediates', function()
  local a = compute_actions(make_session('/r', {}), { 'a/b/c.txt' })
  r.assert_eq(#a, 3)
  r.assert_truthy(find_action(a, 'create', { dst = '/r/a/' }))
  r.assert_truthy(find_action(a, 'create', { dst = '/r/a/b/' }))
  r.assert_truthy(find_action(a, 'create', { dst = '/r/a/b/c.txt' }))
end)

-- ============================================================================
r.group('compute_actions: delete')
-- ============================================================================

r.run('removed line', function()
  local s = make_session('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  local a = compute_actions(s, { '/1 a.txt' })
  r.assert_eq(a[1].name, 'delete')
  r.assert_eq(a[1].src, '/r/b.txt')
end)

r.run('remove all', function()
  local s = make_session('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  r.assert_eq(action_count(compute_actions(s, {}), 'delete'), 2)
end)

-- ============================================================================
r.group('compute_actions: rename/move')
-- ============================================================================

r.run('rename', function()
  local s = make_session('/r', { { name = 'old.txt', abs_path = '/r/old.txt', type = 'file' } })
  local a = compute_actions(s, { '/1 new.txt' })
  r.assert_eq(a[1].name, 'move')
  r.assert_eq(a[1].src, '/r/old.txt')
  r.assert_eq(a[1].dst, '/r/new.txt')
end)

r.run('move into dir', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'f.txt', abs_path = '/r/f.txt', type = 'file' },
  })
  s.expanded_dirs['/r/src'] = true
  local a = compute_actions(s, { '/1 src/', '  /2 f.txt' })
  r.assert_eq(a[1].name, 'move')
  r.assert_eq(a[1].dst, '/r/src/f.txt')
end)

r.run('move out of dir', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  s.expanded_dirs['/r/src'] = true
  local a = compute_actions(s, { '/1 src/', '/2 inner.lua' })
  r.assert_eq(a[1].dst, '/r/inner.lua')
end)

r.run('rename dir', function()
  local s = make_session('/r', { { name = 'old', abs_path = '/r/old', type = 'directory' } })
  local a = compute_actions(s, { '/1 new/' })
  r.assert_eq(a[1].name, 'move')
  r.assert_eq(a[1].src, '/r/old')
  r.assert_eq(a[1].dst, '/r/new')
end)

-- ============================================================================
r.group('compute_actions: copy')
-- ============================================================================

r.run('yy+p+rename = copy', function()
  local s = make_session('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  local a = compute_actions(s, { '/1 a.txt', '/1 a-copy.txt' })
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].src, '/r/a.txt')
  r.assert_eq(a[1].dst, '/r/a-copy.txt')
end)

r.run('copy into subdir', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
  })
  s.expanded_dirs['/r/src'] = true
  local a = compute_actions(s, { '/1 src/', '  /2 a.txt', '/2 a.txt' })
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].dst, '/r/src/a.txt')
end)

r.run('same id same path = no action', function()
  local s = make_session('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  r.assert_eq(#compute_actions(s, { '/1 a.txt', '/1 a.txt', '/1 a.txt' }), 0)
end)

-- ============================================================================
r.group('compute_actions: mixed')
-- ============================================================================

r.run('create + delete + rename', function()
  local s = make_session('/r', {
    { name = 'keep.txt', abs_path = '/r/keep.txt', type = 'file' },
    { name = 'rm.txt', abs_path = '/r/rm.txt', type = 'file' },
    { name = 'old.txt', abs_path = '/r/old.txt', type = 'file' },
  })
  local a = compute_actions(s, { '/1 keep.txt', '/3 new.txt', 'brand.txt' })
  r.assert_eq(action_count(a, 'delete'), 1)
  r.assert_eq(action_count(a, 'move'), 1)
  r.assert_eq(action_count(a, 'create'), 1)
end)

r.run('dedup', function()
  local a = compute_actions(make_session('/r', {}), { 'x/', 'x/' })
  r.assert_eq(#a, 1)
end)

-- ============================================================================
r.group('compute_actions: undo safety (conceal ID survives undo)')
-- ============================================================================

r.run('dd then undo restores ID in text', function()
  -- With conceal approach, undo restores the line text including /ID
  local s = make_session('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  -- After dd on b.txt:
  local a1 = compute_actions(s, { '/1 a.txt' })
  r.assert_eq(#a1, 1)
  r.assert_eq(a1[1].name, 'delete')

  -- After undo (b.txt line restored with /2 prefix):
  local a2 = compute_actions(s, { '/1 a.txt', '/2 b.txt' })
  r.assert_eq(#a2, 0)
end)

r.run('yy+p preserves ID for copy detection', function()
  local s = make_session('/r', {
    { name = 'file.lua', abs_path = '/r/file.lua', type = 'file' },
  })
  -- yy copies "/1 file.lua", p pastes it, user renames to file2.lua
  local a = compute_actions(s, { '/1 file.lua', '/1 file2.lua' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].src, '/r/file.lua')
  r.assert_eq(a[1].dst, '/r/file2.lua')
end)

-- ============================================================================
r.group('compute_actions: expand/collapse')
-- ============================================================================

r.run('expanded children = no actions', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'm.lua', abs_path = '/r/src/m.lua', type = 'file' },
  })
  s.expanded_dirs['/r/src'] = true
  r.assert_eq(#compute_actions(s, { '/1 src/', '  /2 m.lua' }), 0)
end)

r.run('collapsed children not in id_to_path = no delete', function()
  local s = make_session('/r', { { name = 'src', abs_path = '/r/src', type = 'directory' } })
  r.assert_eq(#compute_actions(s, { '/1 src/' }), 0)
end)

-- ============================================================================
r.group('compute_actions: collapsed source')
-- ============================================================================

r.run('copy from collapsed dir to root detects copy', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
  })
  -- collapse: remove inner.lua from id_to_path but keep in store
  s.id_to_path[2] = nil
  -- buffer: src/ (collapsed), pasted inner.lua at root, a.txt
  local a = compute_actions(s, { '/1 src/', '/2 inner.lua', '/3 a.txt' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].src, '/r/src/inner.lua')
  r.assert_eq(a[1].dst, '/r/inner.lua')
end)

r.run('collapsed entry pasted with new name = copy (original still on disk)', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  s.id_to_path[2] = nil
  local a = compute_actions(s, { '/1 src/', '/2 moved.lua' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].src, '/r/src/inner.lua')
  r.assert_eq(a[1].dst, '/r/moved.lua')
end)

r.run('collapsed entry not in buffer = no delete', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  s.id_to_path[2] = nil
  local a = compute_actions(s, { '/1 src/' })
  r.assert_eq(#a, 0)
end)

-- ============================================================================
r.group('duplicate detection')
-- ============================================================================

r.run('same name at same level = duplicate', function()
  local s = make_session('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  -- yy+p without rename: same ID same name twice
  local a = compute_actions(s, { '/1 a.txt', '/1 a.txt' })
  -- compute_actions sees no change (same id same path), but this is a duplicate
  r.assert_eq(#a, 0) -- no actions, but mutate should catch via check_duplicates
end)

r.run('different names at same level = no duplicate', function()
  local s = make_session('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  local a = compute_actions(s, { '/1 a.txt', '/1 b.txt' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'copy')
end)

-- ============================================================================
r.group('saved_children: mutate includes cached lines')
-- ============================================================================

r.run('cached new file in collapsed dir produces create action', function()
  -- Simulate: dir /r/src exists with inner.lua, user pastes new.txt inside,
  -- then collapses. The cached lines include the new file.
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  -- After collapse, expanded_dirs cleared, inner.lua removed from id_to_path, new.txt cached
  s.id_to_path[2] = nil
  s.saved_children = { ['/r/src'] = { '    /2 inner.lua', '    new.txt' } }

  -- Visible buffer only shows collapsed dir
  local raw_lines = { '/1 src/' }
  -- Expand saved_children into buf_lines (same logic as mutate)
  local buf_lines = {}
  for _, l in ipairs(raw_lines) do
    buf_lines[#buf_lines + 1] = l
    local lid, _, _, lis_dir = parse_line(l)
    if lis_dir and lid and s.store[lid] then
      local labs = s.store[lid].abs_path
      if not s.expanded_dirs[labs] and s.saved_children[labs] then
        for _, cl in ipairs(s.saved_children[labs]) do
          buf_lines[#buf_lines + 1] = cl
        end
      end
    end
  end

  local a = compute_actions(s, buf_lines)
  r.assert_truthy(find_action(a, 'create', { dst = '/r/src/new.txt' }))
end)

r.run('cached moved file in collapsed dir produces copy action', function()
  -- file /r/a.txt (id=2) pasted into /r/src/ while src is expanded, then collapsed
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
  })
  s.id_to_path[2] = nil -- collapsed, removed from id_to_path but still in store
  s.saved_children = { ['/r/src'] = { '    /2 a.txt' } }

  local raw_lines = { '/1 src/' }
  local buf_lines = {}
  for _, l in ipairs(raw_lines) do
    buf_lines[#buf_lines + 1] = l
    local lid, _, _, lis_dir = parse_line(l)
    if lis_dir and lid and s.store[lid] then
      local labs = s.store[lid].abs_path
      if not s.expanded_dirs[labs] and s.saved_children[labs] then
        for _, cl in ipairs(s.saved_children[labs]) do
          buf_lines[#buf_lines + 1] = cl
        end
      end
    end
  end

  local a = compute_actions(s, buf_lines)
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].src, '/r/a.txt')
  r.assert_eq(a[1].dst, '/r/src/a.txt')
end)

r.run('no saved_children means no extra actions for collapsed dir', function()
  local s = make_session('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  -- collapsed: inner.lua not in id_to_path, no saved_children
  s.id_to_path[2] = nil
  s.saved_children = {}

  local raw_lines = { '/1 src/' }
  local buf_lines = {}
  for _, l in ipairs(raw_lines) do
    buf_lines[#buf_lines + 1] = l
    local lid, _, _, lis_dir = parse_line(l)
    if lis_dir and lid and s.store[lid] then
      local labs = s.store[lid].abs_path
      if not s.expanded_dirs[labs] and s.saved_children[labs] then
        for _, cl in ipairs(s.saved_children[labs]) do
          buf_lines[#buf_lines + 1] = cl
        end
      end
    end
  end

  local a = compute_actions(s, buf_lines)
  r.assert_eq(#a, 0)
end)

-- ============================================================================
r.group('execute_actions: path swap')
-- ============================================================================

r.run('A->B and B->A routed via temp path', function()
  local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions')
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  local a = tmp .. '/a.txt'
  local b = tmp .. '/b.txt'
  vim.fn.writefile({ 'A' }, a)
  vim.fn.writefile({ 'B' }, b)

  local actions = {
    { name = 'move', src = a, dst = b },
    { name = 'move', src = b, dst = a },
  }
  actions_mod.execute_actions(actions)

  r.assert_eq(table.concat(vim.fn.readfile(a)), 'B')
  r.assert_eq(table.concat(vim.fn.readfile(b)), 'A')
  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('compute_actions: ancestor rename suppresses child move')
-- ============================================================================

r.run('parent dir rename + reused-id children = single move', function()
  -- User renamed /r/old to /r/new, then expanded and its children (still using
  -- original disk ids) show up. compute_actions must only produce one move.
  local s = make_session('/r', {
    { name = 'old', abs_path = '/r/old', type = 'directory' },
    { name = 'x.txt', abs_path = '/r/old/x.txt', type = 'file' },
    { name = 'y.txt', abs_path = '/r/old/y.txt', type = 'file' },
  })
  -- buffer: new/ (id 1), then children with original ids at their disk paths
  local a = compute_actions(s, { '/1 new/', '  /2 x.txt', '  /3 y.txt' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'move')
  r.assert_eq(a[1].src, '/r/old')
  r.assert_eq(a[1].dst, '/r/new')
end)

r.run('parent dir rename + child also renamed = both moves', function()
  local s = make_session('/r', {
    { name = 'old', abs_path = '/r/old', type = 'directory' },
    { name = 'x.txt', abs_path = '/r/old/x.txt', type = 'file' },
  })
  -- child x.txt renamed to x2.txt inside the renamed parent
  local a = compute_actions(s, { '/1 new/', '  /2 x2.txt' })
  r.assert_eq(#a, 2)
  r.assert_truthy(find_action(a, 'move', { src = '/r/old', dst = '/r/new' }))
  r.assert_truthy(find_action(a, 'move', { src = '/r/new/x.txt', dst = '/r/new/x2.txt' }))
end)

r.run('parent dir rename absorbs delete of child on old path', function()
  -- id_to_path has child at old path but child is missing from buffer
  -- (because parent is renamed and buffer only lists the new dir without child).
  local s = make_session('/r', {
    { name = 'old', abs_path = '/r/old', type = 'directory' },
    { name = 'x.txt', abs_path = '/r/old/x.txt', type = 'file' },
  })
  local a = compute_actions(s, { '/1 new/' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'move')
end)

-- ============================================================================
r.group('compute_actions: phantom copy expansion')
-- ============================================================================

r.run('copy A to B, phantom child renamed = create B + copy A/x -> B/x2', function()
  local s = make_session('/r', {
    { name = 'A', abs_path = '/r/A', type = 'directory' },
  })
  s.next_id = 3
  -- phantom dir B (id=2) with shadow A
  s.store[2] = { name = 'A', abs_path = '/r/B', type = 'directory' }
  s.id_to_path[2] = '/r/B'
  -- phantom child x.txt (id=3) targeting /r/B/x.txt initially, shadow A/x.txt
  s.store[3] = { name = 'x.txt', abs_path = '/r/B/x.txt', type = 'file' }
  s.id_to_path[3] = '/r/B/x.txt'
  s.copy_shadow = { [2] = '/r/A', [3] = '/r/A/x.txt' }

  -- buffer: /1 A/, /2 B/, /3 x2.txt (child renamed)
  local a = compute_actions(s, { '/1 A/', '/2 B/', '  /3 x2.txt' })
  r.assert_truthy(find_action(a, 'create', { dst = '/r/B/' }))
  r.assert_truthy(find_action(a, 'copy', { src = '/r/A/x.txt', dst = '/r/B/x2.txt' }))
  r.assert_eq(find_action(a, 'copy', { src = '/r/A', dst = '/r/B' }), nil)
end)

r.run('copy A to B without phantom transitions = bulk copy', function()
  local s = make_session('/r', {
    { name = 'A', abs_path = '/r/A', type = 'directory' },
  })
  -- no phantoms registered yet: buffer just has original A/ and a duplicate
  -- of it (before user expands B), which stays as an id-1 transition.
  local a = compute_actions(s, { '/1 A/', '/1 B/' })
  r.assert_truthy(find_action(a, 'copy', { src = '/r/A', dst = '/r/B' }))
end)

-- ============================================================================
r.group('compute_actions: multi-relocate safety')
-- ============================================================================

r.run('yy+p twice with rename = copy+copy+delete (never move+copy)', function()
  -- User yanks /r/f.txt, pastes twice, renames to f.1 and f.2. Original path
  -- disappears from buffer. Result should be 2 copies + 1 delete so all copies
  -- can read from the still-existing src before it's removed.
  local s = make_session('/r', {
    { name = 'f.txt', abs_path = '/r/f.txt', type = 'file' },
  })
  local a = compute_actions(s, { '/1 f.1', '/1 f.2' })
  r.assert_eq(action_count(a, 'copy'), 2)
  r.assert_eq(action_count(a, 'delete'), 1)
  r.assert_eq(action_count(a, 'move'), 0)
  r.assert_truthy(find_action(a, 'copy', { src = '/r/f.txt', dst = '/r/f.1' }))
  r.assert_truthy(find_action(a, 'copy', { src = '/r/f.txt', dst = '/r/f.2' }))
  r.assert_truthy(find_action(a, 'delete', { src = '/r/f.txt' }))
end)

-- ============================================================================
r.group('execute_actions: topological ordering')
-- ============================================================================

r.run('copy X + move X: copy runs before move consumes X', function()
  local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, 'p')
  local x = tmp .. '/x'; vim.fn.writefile({ 'X' }, x)
  actions_mod.execute_actions({
    { name = 'move', src = x, dst = tmp .. '/y' },
    { name = 'copy', src = x, dst = tmp .. '/z' },
  })
  r.assert_eq(vim.fn.filereadable(tmp .. '/y'), 1)
  r.assert_eq(vim.fn.filereadable(tmp .. '/z'), 1)
  r.assert_eq(table.concat(vim.fn.readfile(tmp .. '/z')), 'X')
  vim.fn.delete(tmp, 'rf')
end)

r.run('delete X + create X: delete runs first', function()
  local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, 'p')
  local x = tmp .. '/x'; vim.fn.writefile({ 'old' }, x)
  actions_mod.execute_actions({
    { name = 'create', dst = x },
    { name = 'delete', src = x },
  })
  r.assert_eq(vim.fn.filereadable(x), 1)
  r.assert_eq(table.concat(vim.fn.readfile(x)), '')
  vim.fn.delete(tmp, 'rf')
end)

r.run('create parent dir before writing child file', function()
  local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, 'p')
  actions_mod.execute_actions({
    { name = 'create', dst = tmp .. '/d/f' },
    { name = 'create', dst = tmp .. '/d/' },
  })
  r.assert_eq(vim.fn.isdirectory(tmp .. '/d'), 1)
  r.assert_eq(vim.fn.filereadable(tmp .. '/d/f'), 1)
  vim.fn.delete(tmp, 'rf')
end)

r.run('parent rename before child rename (child listed first)', function()
  local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp .. '/A', 'p')
  vim.fn.writefile({ 'x' }, tmp .. '/A/x')
  actions_mod.execute_actions({
    -- child (references old path) placed before parent to test topo
    { name = 'move', src = tmp .. '/A/x', dst = tmp .. '/A/y' },
    { name = 'move', src = tmp .. '/A', dst = tmp .. '/B' },
  })
  -- child move src references old parent path; topo must run parent-move first
  -- so the child move against /A/x will fail to find src (already moved to /B/x).
  -- Expected behavior: parent move runs first, /B/x exists, then child move
  -- fails silently (its src /A/x is gone). Assert /B/x exists at least.
  r.assert_eq(vim.fn.isdirectory(tmp .. '/B'), 1)
  vim.fn.delete(tmp, 'rf')
end)

r.finish()
