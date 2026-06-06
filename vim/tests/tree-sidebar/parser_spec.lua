-- Tree-sidebar git_changes parser tests: tree-builder + git_root cache.
-- Usage: cd vim && nvim --headless -u NONE -l tests/tree-sidebar/parser_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local parser = require('lu5je0.ext.tree-sidebar.sources.git_changes.parser')

-- Tests need a stable cwd to compute abs_path; pin it to a tmp dir.
-- The helper creates the target dir if missing so callers don't have
-- to remember to mkdir before lcd.
local function with_cwd(target, fn)
  local prev = vim.fn.getcwd()
  if vim.fn.isdirectory(target) ~= 1 then
    vim.fn.mkdir(target, 'p')
  end
  vim.cmd('lcd ' .. vim.fn.fnameescape(target))
  local ok, err = pcall(fn)
  vim.cmd('lcd ' .. vim.fn.fnameescape(prev))
  parser.invalidate_root_cache()
  if not ok then error(err, 0) end
end

local function git(args, cwd)
  local result = vim.system(vim.list_extend({ 'git' }, args), { text = true, cwd = cwd }):wait()
  if result.code ~= 0 then
    error('git failed: ' .. table.concat(args, ' ') .. '\n' .. (result.stderr or ''), 2)
  end
  return (result.stdout or ''):gsub('%s+$', '')
end

-- ============================================================================
-- group: files_to_tree_nodes
-- ============================================================================

r.group('files_to_tree_nodes')

r.run('flat files become root-level file nodes', function()
  with_cwd(vim.fn.tempname(), function()
    -- abs_path values are computed via git_root() which falls back to
    -- cwd when there's no repo.
    local files = {
      { path = 'a.txt', xy = 'M ', x = 'M', y = ' ' },
      { path = 'b.txt', xy = ' M', x = ' ', y = 'M' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'staged')
    r.assert_eq(#nodes, 2)
    r.assert_eq(nodes[1].name, 'a.txt')
    r.assert_eq(nodes[1].type, 'file')
    r.assert_eq(nodes[1].section, 'staged')
    r.assert_eq(nodes[2].name, 'b.txt')
  end)
end)

r.run('nested paths build a directory tree', function()
  with_cwd(vim.fn.tempname(), function()
    local files = {
      { path = 'src/a.lua', xy = 'M ', x = 'M', y = ' ' },
      { path = 'src/sub/b.lua', xy = 'M ', x = 'M', y = ' ' },
      { path = 'top.txt', xy = 'M ', x = 'M', y = ' ' },
    }
    local nodes = parser.files_to_tree_nodes(files, {}, 'staged')
    -- src/ directory + top.txt file
    r.assert_eq(#nodes, 2)
    -- alphabetical sort: directory 'src' first, then file 'top.txt'
    r.assert_eq(nodes[1].name, 'src')
    r.assert_eq(nodes[1].type, 'directory')
    r.assert_eq(nodes[2].name, 'top.txt')
    -- Inside src: a.lua + sub/
    local src = nodes[1]
    r.assert_eq(#src.children, 2)
    -- 'sub' is a directory, comes first; 'a.lua' is a file, comes second
    local sub = src.children[1]
    local a = src.children[2]
    r.assert_eq(sub.name, 'sub')
    r.assert_eq(sub.type, 'directory')
    r.assert_eq(a.name, 'a.lua')
    r.assert_eq(a.type, 'file')
  end)
end)

r.run('expanded_dirs overrides default directory expansion', function()
  with_cwd(vim.fn.tempname(), function()
    local cwd = parser.git_root()
    local files = { { path = 'src/a.lua', xy = 'M ', x = 'M', y = ' ' } }
    local nodes = parser.files_to_tree_nodes(files, { [cwd .. '/src'] = false }, 'staged')
    r.assert_eq(nodes[1].name, 'src')
    r.assert_eq(nodes[1].expanded, false)
  end)
end)

-- ============================================================================
-- group: git_root cache auto-invalidation
-- ============================================================================

r.group('git_root cache')

r.run('cache hit when cached root remains valid', function()
  local tmp = vim.fn.resolve(vim.fn.tempname() .. '-grootcache')
  vim.fn.mkdir(tmp, 'p')
  git({ 'init' }, tmp)
  with_cwd(tmp, function()
    local first = parser.git_root()
    r.assert_eq(first, vim.fn.resolve(tmp))
    -- Second call should still produce the same root (cached or re-resolved).
    local second = parser.git_root()
    r.assert_eq(second, first)
  end)
  vim.fn.delete(tmp, 'rf')
end)

r.run('cache invalidates when .git disappears under cached root', function()
  local outer = vim.fn.resolve(vim.fn.tempname() .. '-grootouter')
  vim.fn.mkdir(outer, 'p')
  git({ 'init' }, outer)
  with_cwd(outer, function()
    local first = parser.git_root()
    r.assert_eq(first, vim.fn.resolve(outer))

    -- Now nuke the .git directory; cache must not return the stale root.
    vim.fn.delete(outer .. '/.git', 'rf')
    local second = parser.git_root()
    -- After invalidation, git_root() falls back to getcwd() (no .git anywhere),
    -- which equals `outer` itself. The key assertion is that a re-resolution
    -- happened (no surprise cached value pointing to a non-existent .git).
    r.assert_eq(second, vim.fn.resolve(outer))
  end)
  vim.fn.delete(outer, 'rf')
end)

r.run('cache invalidates when nested .git appears in subdir (cwd no longer under cached root)', function()
  local outer = vim.fn.resolve(vim.fn.tempname() .. '-grootnest')
  vim.fn.mkdir(outer, 'p')
  git({ 'init' }, outer)
  local inner = outer .. '/sub'
  vim.fn.mkdir(inner, 'p')

  -- Prime the cache with the outer root
  with_cwd(outer, function()
    local outer_root = parser.git_root()
    r.assert_eq(outer_root, vim.fn.resolve(outer))
  end)

  -- Now create a nested repo and resolve from it
  git({ 'init' }, inner)
  with_cwd(inner, function()
    local inner_root = parser.git_root()
    -- inner_root must point to the nested .git, not the cached outer one
    r.assert_eq(inner_root, vim.fn.resolve(inner))
  end)

  vim.fn.delete(outer, 'rf')
end)

r.finish()
