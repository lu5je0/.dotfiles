-- fs-edit tests: parse_line + model reconcile/diff (conceal /NNN approach).
-- Usage: cd vim && nvim --headless -u NONE -l tests/sidebar/fs_edit_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local te = require('lu5je0.ext.sidebar.sources.files.fs-edit')
local model_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.model')
local parse_line = te._parse_line

-- Build a model whose snapshot contains `entries` (ordered; ids assigned
-- 1..n). Entries nested under an earlier directory entry are attached as its
-- (collapsed) stash children, mirroring what scan_children produces.
local function make_model(root_dir, entries)
  local m = model_mod.new(root_dir)
  local by_path = {}
  for _, e in ipairs(entries or {}) do
    local id = model_mod.mint_disk(m, e.abs_path, e.name, e.type)
    m.disk[id].tracked = true
    local node = {
      kind = 'entity', id = id, name = e.name, type = e.type,
      expanded = false, loaded = false, children = {},
    }
    m.nodes[id] = node
    by_path[e.abs_path] = node
    local parent = by_path[vim.fs.dirname(e.abs_path)]
    if parent then
      parent.loaded = true
      parent.children[#parent.children + 1] = node
    else
      m.root.children[#m.root.children + 1] = node
    end
  end
  m.root.loaded = true
  return m
end

local function compute(m, lines)
  model_mod.reconcile(m, lines)
  return model_mod.diff(m)
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

r.run('odd indent floors depth', function()
  local _, _, depth = parse_line('   /3 odd.txt')
  r.assert_eq(depth, 1)
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
r.group('diff: no changes')
-- ============================================================================

r.run('unchanged buffer', function()
  local m = make_model('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  r.assert_eq(#compute(m, { '/1 a.txt', '/2 b.txt' }), 0)
end)

r.run('unchanged expanded dir', function()
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'main.lua', abs_path = '/r/src/main.lua', type = 'file' },
  })
  r.assert_eq(#compute(m, { '/1 src/', '  /2 main.lua' }), 0)
end)

r.run('swapping order', function()
  local m = make_model('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  r.assert_eq(#compute(m, { '/2 b.txt', '/1 a.txt' }), 0)
end)

r.run('dir trailing slash no spurious move', function()
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'lib', abs_path = '/r/lib', type = 'directory' },
  })
  r.assert_eq(#compute(m, { '/1 src/', '/2 lib/' }), 0)
end)

-- ============================================================================
r.group('diff: create')
-- ============================================================================

r.run('new file (no id)', function()
  local m = make_model('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  local a = compute(m, { '/1 a.txt', 'new.txt' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'create')
  r.assert_eq(a[1].dst, '/r/new.txt')
end)

r.run('new dir', function()
  local a = compute(make_model('/r', {}), { 'newdir/' })
  r.assert_eq(a[1].dst, '/r/newdir/')
end)

r.run('new file inside dir', function()
  local m = make_model('/r', { { name = 'src', abs_path = '/r/src', type = 'directory' } })
  local a = compute(m, { '/1 src/', '  new.lua' })
  r.assert_eq(a[1].dst, '/r/src/new.lua')
end)

r.run('nested path creates intermediates', function()
  local a = compute(make_model('/r', {}), { 'a/b/c.txt' })
  r.assert_eq(#a, 3)
  r.assert_truthy(find_action(a, 'create', { dst = '/r/a/' }))
  r.assert_truthy(find_action(a, 'create', { dst = '/r/a/b/' }))
  r.assert_truthy(find_action(a, 'create', { dst = '/r/a/b/c.txt' }))
end)

-- ============================================================================
r.group('diff: delete')
-- ============================================================================

r.run('removed line', function()
  local m = make_model('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  local a = compute(m, { '/1 a.txt' })
  r.assert_eq(a[1].name, 'delete')
  r.assert_eq(a[1].src, '/r/b.txt')
end)

r.run('remove all', function()
  local m = make_model('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  r.assert_eq(action_count(compute(m, {}), 'delete'), 2)
end)

-- ============================================================================
r.group('diff: rename/move')
-- ============================================================================

r.run('rename', function()
  local m = make_model('/r', { { name = 'old.txt', abs_path = '/r/old.txt', type = 'file' } })
  local a = compute(m, { '/1 new.txt' })
  r.assert_eq(a[1].name, 'move')
  r.assert_eq(a[1].src, '/r/old.txt')
  r.assert_eq(a[1].dst, '/r/new.txt')
end)

r.run('move into dir', function()
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'f.txt', abs_path = '/r/f.txt', type = 'file' },
  })
  local a = compute(m, { '/1 src/', '  /2 f.txt' })
  r.assert_eq(a[1].name, 'move')
  r.assert_eq(a[1].dst, '/r/src/f.txt')
end)

r.run('move out of dir', function()
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  -- src expanded: child line moved to root, dir line has no children left
  local a = compute(m, { '/1 src/', '/2 inner.lua' })
  r.assert_eq(a[1].dst, '/r/inner.lua')
end)

r.run('rename dir', function()
  local m = make_model('/r', { { name = 'old', abs_path = '/r/old', type = 'directory' } })
  local a = compute(m, { '/1 new/' })
  r.assert_eq(a[1].name, 'move')
  r.assert_eq(a[1].src, '/r/old')
  r.assert_eq(a[1].dst, '/r/new')
end)

-- ============================================================================
r.group('diff: copy')
-- ============================================================================

r.run('yy+p+rename = copy', function()
  local m = make_model('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  local a = compute(m, { '/1 a.txt', '/1 a-copy.txt' })
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].src, '/r/a.txt')
  r.assert_eq(a[1].dst, '/r/a-copy.txt')
end)

r.run('copy into subdir', function()
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
  })
  local a = compute(m, { '/1 src/', '  /2 a.txt', '/2 a.txt' })
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].dst, '/r/src/a.txt')
end)

r.run('same id same path = no action', function()
  local m = make_model('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  r.assert_eq(#compute(m, { '/1 a.txt', '/1 a.txt', '/1 a.txt' }), 0)
end)

-- ============================================================================
r.group('diff: mixed')
-- ============================================================================

r.run('create + delete + rename', function()
  local m = make_model('/r', {
    { name = 'keep.txt', abs_path = '/r/keep.txt', type = 'file' },
    { name = 'rm.txt', abs_path = '/r/rm.txt', type = 'file' },
    { name = 'old.txt', abs_path = '/r/old.txt', type = 'file' },
  })
  local a = compute(m, { '/1 keep.txt', '/3 new.txt', 'brand.txt' })
  r.assert_eq(action_count(a, 'delete'), 1)
  r.assert_eq(action_count(a, 'move'), 1)
  r.assert_eq(action_count(a, 'create'), 1)
end)

r.run('dedup', function()
  local a = compute(make_model('/r', {}), { 'x/', 'x/' })
  r.assert_eq(#a, 1)
end)

-- ============================================================================
r.group('diff: undo safety (conceal ID survives undo)')
-- ============================================================================

r.run('dd then undo restores ID in text', function()
  -- With the conceal approach undo restores the line text including /ID; the
  -- reconciled model re-claims the node together with its state.
  local m = make_model('/r', {
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
    { name = 'b.txt', abs_path = '/r/b.txt', type = 'file' },
  })
  local a1 = compute(m, { '/1 a.txt' })
  r.assert_eq(#a1, 1)
  r.assert_eq(a1[1].name, 'delete')

  local a2 = compute(m, { '/1 a.txt', '/2 b.txt' })
  r.assert_eq(#a2, 0)
end)

r.run('yy+p preserves ID for copy detection', function()
  local m = make_model('/r', {
    { name = 'file.lua', abs_path = '/r/file.lua', type = 'file' },
  })
  local a = compute(m, { '/1 file.lua', '/1 file2.lua' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].src, '/r/file.lua')
  r.assert_eq(a[1].dst, '/r/file2.lua')
end)

-- ============================================================================
r.group('diff: expand/collapse')
-- ============================================================================

r.run('expanded children = no actions', function()
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'm.lua', abs_path = '/r/src/m.lua', type = 'file' },
  })
  r.assert_eq(#compute(m, { '/1 src/', '  /2 m.lua' }), 0)
end)

r.run('never-loaded collapsed dir = no actions', function()
  local m = make_model('/r', { { name = 'src', abs_path = '/r/src', type = 'directory' } })
  r.assert_eq(#compute(m, { '/1 src/' }), 0)
end)

-- ============================================================================
r.group('diff: collapsed stash source')
-- ============================================================================

r.run('copy from collapsed dir to root detects copy', function()
  -- inner.lua lives in src's collapsed stash AND is pasted at root:
  -- the stash position sits at the disk path, so the root line is a copy.
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
  })
  local a = compute(m, { '/1 src/', '/2 inner.lua', '/3 a.txt' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].src, '/r/src/inner.lua')
  r.assert_eq(a[1].dst, '/r/inner.lua')
end)

r.run('collapsed stash entry pasted with new name = copy', function()
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  local a = compute(m, { '/1 src/', '/2 moved.lua' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(a[1].src, '/r/src/inner.lua')
  r.assert_eq(a[1].dst, '/r/moved.lua')
end)

r.run('collapsed stash entry not in buffer = no delete', function()
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  local a = compute(m, { '/1 src/' })
  r.assert_eq(#a, 0)
end)

-- ============================================================================
r.group('duplicate detection')
-- ============================================================================

r.run('same name at same level = duplicate', function()
  local m = make_model('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  local a = compute(m, { '/1 a.txt', '/1 a.txt' })
  r.assert_eq(#a, 0) -- no actions, but check_dupes must flag it
  local dupes = model_mod.check_dupes(m)
  r.assert_eq(#dupes, 1)
  r.assert_eq(dupes[1], 'a.txt')
end)

r.run('different names at same level = no duplicate', function()
  local m = make_model('/r', { { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' } })
  local a = compute(m, { '/1 a.txt', '/1 b.txt' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'copy')
  r.assert_eq(#model_mod.check_dupes(m), 0)
end)

-- ============================================================================
r.group('stash: hidden edits participate in diff')
-- ============================================================================

r.run('new file stashed in collapsed dir produces create action', function()
  -- User typed new.txt under expanded src, then collapsed: the create element
  -- is stashed inside the node's children and must still emit on save.
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  local src = m.nodes[1]
  src.children[#src.children + 1] =
    { kind = 'create', name = 'new.txt', type = 'file', children = {} }

  local a = compute(m, { '/1 src/' })
  r.assert_truthy(find_action(a, 'create', { dst = '/r/src/new.txt' }))
end)

r.run('root file moved into collapsed stash = move', function()
  -- a.txt's line was deleted at root and its node now lives only inside the
  -- collapsed src stash: the model reads that as a move (the old architecture
  -- degraded this to a copy because collapse bookkeeping lost the intent).
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'a.txt', abs_path = '/r/a.txt', type = 'file' },
  })
  local src, a_node = m.nodes[1], m.nodes[2]
  -- detach a.txt from root, stash it under src
  for i, c in ipairs(m.root.children) do
    if c == a_node then table.remove(m.root.children, i) break end
  end
  src.loaded = true
  src.children[#src.children + 1] = a_node

  local a = compute(m, { '/1 src/' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'move')
  r.assert_eq(a[1].src, '/r/a.txt')
  r.assert_eq(a[1].dst, '/r/src/a.txt')
end)

r.run('untouched stash means no extra actions for collapsed dir', function()
  local m = make_model('/r', {
    { name = 'src', abs_path = '/r/src', type = 'directory' },
    { name = 'inner.lua', abs_path = '/r/src/inner.lua', type = 'file' },
  })
  r.assert_eq(#compute(m, { '/1 src/' }), 0)
end)

-- ============================================================================
r.group('execute_actions: path swap')
-- ============================================================================

r.run('A->B and B->A routed via temp path', function()
  local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
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
r.group('diff: ancestor rename suppresses child move')
-- ============================================================================

r.run('parent dir rename + reused-id children = single move', function()
  local m = make_model('/r', {
    { name = 'old', abs_path = '/r/old', type = 'directory' },
    { name = 'x.txt', abs_path = '/r/old/x.txt', type = 'file' },
    { name = 'y.txt', abs_path = '/r/old/y.txt', type = 'file' },
  })
  local a = compute(m, { '/1 new/', '  /2 x.txt', '  /3 y.txt' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'move')
  r.assert_eq(a[1].src, '/r/old')
  r.assert_eq(a[1].dst, '/r/new')
end)

r.run('parent dir rename + child also renamed = both moves', function()
  local m = make_model('/r', {
    { name = 'old', abs_path = '/r/old', type = 'directory' },
    { name = 'x.txt', abs_path = '/r/old/x.txt', type = 'file' },
  })
  local a = compute(m, { '/1 new/', '  /2 x2.txt' })
  r.assert_eq(#a, 2)
  r.assert_truthy(find_action(a, 'move', { src = '/r/old', dst = '/r/new' }))
  r.assert_truthy(find_action(a, 'move', { src = '/r/new/x.txt', dst = '/r/new/x2.txt' }))
end)

r.run('parent dir rename absorbs child carried in the collapsed stash', function()
  -- child lives in the stash; the parent rename carries it implicitly.
  local m = make_model('/r', {
    { name = 'old', abs_path = '/r/old', type = 'directory' },
    { name = 'x.txt', abs_path = '/r/old/x.txt', type = 'file' },
  })
  local a = compute(m, { '/1 new/' })
  r.assert_eq(#a, 1)
  r.assert_eq(a[1].name, 'move')
end)

-- ============================================================================
r.group('diff: copy node expansion')
-- ============================================================================

r.run('copy A to B, copied child renamed = create B + copy A/x -> B/x2', function()
  local m = make_model('/r', {
    { name = 'A', abs_path = '/r/A', type = 'directory' },
    { name = 'x.txt', abs_path = '/r/A/x.txt', type = 'file' },
  })
  -- persistent copy node B (id 3) with a materialized copied child (id 4)
  local b = { kind = 'copy', id = 3, origin = 1, name = 'B', type = 'directory',
              expanded = true, loaded = true, children = {} }
  local bx = { kind = 'copy', id = 4, origin = 2, name = 'x.txt', type = 'file', children = {} }
  b.children[1] = bx
  m.nodes[3], m.nodes[4] = b, bx
  m.next_id = 5

  local a = compute(m, { '/1 A/', '/3 B/', '  /4 x2.txt' })
  r.assert_truthy(find_action(a, 'create', { dst = '/r/B/' }))
  r.assert_truthy(find_action(a, 'copy', { src = '/r/A/x.txt', dst = '/r/B/x2.txt' }))
  r.assert_eq(find_action(a, 'copy', { src = '/r/A', dst = '/r/B' }), nil)
end)

r.run('duplicated dir line without expansion = bulk copy', function()
  local m = make_model('/r', {
    { name = 'A', abs_path = '/r/A', type = 'directory' },
  })
  local a = compute(m, { '/1 A/', '/1 B/' })
  r.assert_truthy(find_action(a, 'copy', { src = '/r/A', dst = '/r/B' }))
end)

-- ============================================================================
r.group('diff: multi-relocate safety')
-- ============================================================================

r.run('yy+p twice with rename = copy + move (last one is move)', function()
  local m = make_model('/r', {
    { name = 'f.txt', abs_path = '/r/f.txt', type = 'file' },
  })
  local a = compute(m, { '/1 f.1', '/1 f.2' })
  r.assert_eq(action_count(a, 'copy'), 1)
  r.assert_eq(action_count(a, 'move'), 1)
  r.assert_eq(action_count(a, 'delete'), 0)
  r.assert_truthy(find_action(a, 'copy', { src = '/r/f.txt', dst = '/r/f.1' }))
  r.assert_truthy(find_action(a, 'move', { src = '/r/f.txt', dst = '/r/f.2' }))
end)

-- ============================================================================
r.group('execute_actions: topological ordering')
-- ============================================================================

r.run('copy X + move X: copy runs before move consumes X', function()
  local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
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
  local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
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
  local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, 'p')
  actions_mod.execute_actions({
    { name = 'create', dst = tmp .. '/d/f' },
    { name = 'create', dst = tmp .. '/d/' },
  })
  r.assert_eq(vim.fn.isdirectory(tmp .. '/d'), 1)
  r.assert_eq(vim.fn.filereadable(tmp .. '/d/f'), 1)
  vim.fn.delete(tmp, 'rf')
end)

r.run('child move in pre-rename world runs before parent rename', function()
  local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp .. '/A', 'p')
  vim.fn.writefile({ 'x' }, tmp .. '/A/x')
  actions_mod.execute_actions({
    -- child (references old path) placed before parent to test topo
    { name = 'move', src = tmp .. '/A/x', dst = tmp .. '/A/y' },
    { name = 'move', src = tmp .. '/A', dst = tmp .. '/B' },
  })
  -- child move operates on pre-rename paths, so it must run first (A/x -> A/y),
  -- then the parent rename carries it along: final state is B/y.
  r.assert_eq(vim.fn.isdirectory(tmp .. '/B'), 1)
  r.assert_eq(vim.fn.filereadable(tmp .. '/B/y'), 1)
  r.assert_eq(vim.fn.filereadable(tmp .. '/B/x'), 0)
  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('confirm.detect_conflicts')
-- ============================================================================

r.run('move to existing path flagged as conflict', function()
  local confirm = require('lu5je0.ext.sidebar.sources.files.fs-edit.confirm')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, 'p')
  local a = tmp .. '/a.txt'; vim.fn.writefile({ 'a' }, a)
  local b = tmp .. '/b.txt'; vim.fn.writefile({ 'b' }, b)
  local action = { name = 'move', src = a, dst = b }
  local conflicts = confirm.detect_conflicts({ action })
  r.assert_eq(conflicts[action], true)
  vim.fn.delete(tmp, 'rf')
end)

r.run('move over existing path is not conflict when delete frees it', function()
  local confirm = require('lu5je0.ext.sidebar.sources.files.fs-edit.confirm')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, 'p')
  local existing = tmp .. '/Regular.ttf'; vim.fn.writefile({ 'old' }, existing)
  local rename_src = tmp .. '/Regular (2).ttf'; vim.fn.writefile({ 'new' }, rename_src)
  local del = { name = 'delete', src = existing }
  local mv = { name = 'move', src = rename_src, dst = existing }
  local conflicts = confirm.detect_conflicts({ del, mv })
  r.assert_eq(conflicts[mv], nil)
  r.assert_eq(conflicts[del], nil)
  vim.fn.delete(tmp, 'rf')
end)

r.run('move over existing path is not conflict when another move relocates it', function()
  local confirm = require('lu5je0.ext.sidebar.sources.files.fs-edit.confirm')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, 'p')
  local a = tmp .. '/a.txt'; vim.fn.writefile({ 'a' }, a)
  local b = tmp .. '/b.txt'; vim.fn.writefile({ 'b' }, b)
  local c = tmp .. '/c.txt'
  local mv1 = { name = 'move', src = a, dst = b }
  local mv2 = { name = 'move', src = b, dst = c }
  local conflicts = confirm.detect_conflicts({ mv2, mv1 })
  r.assert_eq(conflicts[mv1], nil)
  r.assert_eq(conflicts[mv2], nil)
  vim.fn.delete(tmp, 'rf')
end)

r.run('missing src flagged as conflict (stale snapshot)', function()
  local confirm = require('lu5je0.ext.sidebar.sources.files.fs-edit.confirm')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, 'p')
  local mv = { name = 'move', src = tmp .. '/ghost.txt', dst = tmp .. '/dst.txt' }
  local conflicts, missing = confirm.detect_conflicts({ mv })
  r.assert_eq(conflicts[mv], true)
  r.assert_eq(missing[mv], true)
  vim.fn.delete(tmp, 'rf')
end)

r.run('missing src not flagged when produced by another action in the batch', function()
  local confirm = require('lu5je0.ext.sidebar.sources.files.fs-edit.confirm')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, 'p')
  local a = tmp .. '/a.txt'; vim.fn.writefile({ 'a' }, a)
  local staged = tmp .. '/a.txt.fs-edit-swap-1'
  local s1 = { name = 'move', src = a, dst = staged }
  local s2 = { name = 'move', src = staged, dst = tmp .. '/b.txt' }
  local conflicts, missing = confirm.detect_conflicts({ s1, s2 })
  r.assert_eq(conflicts[s2], nil)
  r.assert_eq(missing[s2], nil)
  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('plan_actions: dependency cycle aborts the save')
-- ============================================================================

r.run('unresolvable cycle returns nil and execute_actions runs nothing', function()
  local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
  local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp .. '/A', 'p')
  vim.fn.writefile({ 'x' }, tmp .. '/A/f')
  -- move A -> B requires A freed before B/x... while move B -> A/x requires B
  -- freed before writing under A: mutually contradictory, cannot be ordered.
  local acts = {
    { name = 'move', src = tmp .. '/A', dst = tmp .. '/B' },
    { name = 'move', src = tmp .. '/B', dst = tmp .. '/A/x' },
  }
  local ordered, err = actions_mod.plan_actions(acts)
  r.assert_eq(ordered, nil)
  r.assert_truthy(err and err:find('cycle') ~= nil, 'error mentions cycle')

  local orig_notify = vim.notify
  vim.notify = function() end
  local ok = actions_mod.execute_actions(acts)
  vim.notify = orig_notify
  r.assert_eq(ok, false)
  r.assert_truthy(vim.uv.fs_stat(tmp .. '/A/f') ~= nil, 'source tree untouched')
  r.assert_eq(vim.uv.fs_stat(tmp .. '/B'), nil, 'no partial move executed')
  vim.fn.delete(tmp, 'rf')
end)

r.finish()
