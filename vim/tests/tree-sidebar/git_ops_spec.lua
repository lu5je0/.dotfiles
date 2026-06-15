-- Tree-sidebar git_ops integration tests.
-- Spins up real git repos, real stage/unstage/discard operations with undo.
-- Usage: cd vim && nvim --headless -u NONE -l tests/tree-sidebar/git_ops_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local color = h.color

local git_ops = require('lu5je0.ext.git.common.git-ops')

local passed, failed = 0, 0

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format('%s\n      actual:   %s\n      expected: %s',
      msg or 'mismatch', tostring(actual), tostring(expected)), 2)
  end
end

local function assert_truthy(v, msg)
  if not v then error(msg or 'expected truthy', 2) end
end

local function git(args, cwd)
  local cmd = { 'git' }
  for _, a in ipairs(args) do cmd[#cmd + 1] = a end
  local result = vim.system(cmd, { text = true, cwd = cwd }):wait()
  assert(result.code == 0, 'git failed: ' .. table.concat(cmd, ' ') .. '\n' .. (result.stderr or ''))
  return (result.stdout or ''):gsub('%s+$', '')
end

local function write_file(path, content)
  local fd = assert(io.open(path, 'w'))
  fd:write(content or '')
  fd:close()
end

local function read_file(path)
  local fd = io.open(path, 'r')
  if not fd then return nil end
  local content = fd:read('*a')
  fd:close()
  return content
end

local function file_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

local function make_git_repo()
  local root = vim.fn.resolve(vim.fn.tempname() .. '-gitops')
  vim.fn.mkdir(root, 'p')
  git({ 'init' }, root)
  git({ 'config', 'user.email', 'test@test.com' }, root)
  git({ 'config', 'user.name', 'Test' }, root)
  write_file(root .. '/base.txt', 'base content\n')
  git({ 'add', 'base.txt' }, root)
  git({ 'commit', '-m', 'init' }, root)
  return root
end

local function rmrf(path)
  if path and path ~= '' and path:match('/tmp') then
    vim.fn.delete(path, 'rf')
  end
end

local function run(name, fn)
  io.write('  ' .. name .. ' ... ')
  local root = make_git_repo()
  local ok, err = pcall(fn, root)
  rmrf(root)
  if ok then
    io.write(color.green .. 'PASS' .. color.reset .. '\n')
    passed = passed + 1
  else
    io.write(color.red .. 'FAIL' .. color.reset .. '\n    ' .. tostring(err) .. '\n')
    failed = failed + 1
  end
end

-- helper: get staged files
local function staged_files(cwd)
  local out = git({ 'diff', '--cached', '--name-only' }, cwd)
  if out == '' then return {} end
  local files = {}
  for line in out:gmatch('[^\n]+') do files[#files + 1] = line end
  return files
end

-- helper: get working tree status
local function status_short(cwd)
  return git({ 'status', '--porcelain' }, cwd)
end

-- ============================================================================
-- group: undo index verification (reset_paths / add_paths)
-- ============================================================================

io.write(color.cyan .. 'undo index verification' .. color.reset .. '\n')

run('undo reset_paths succeeds when index unchanged', function(root)
  write_file(root .. '/new.lua', 'hello\n')
  git({ 'add', 'new.lua' }, root)

  -- Simulate: user staged new.lua, undo = reset it
  local snapshot = git_ops.index_snapshot(root, { 'new.lua' })
  local stack = {}
  git_ops.push_undo(stack, 'staged', { { type = 'reset_paths', paths = { 'new.lua' }, expected_index = snapshot } })

  -- Undo should succeed (index unchanged)
  git_ops.undo_last_action(stack, root, function() end)

  -- new.lua should be unstaged now
  local s = status_short(root)
  assert_truthy(s:find('%?%? new.lua'), 'expected new.lua to be untracked after undo')
end)

run('undo reset_paths fails when index changed', function(root)
  write_file(root .. '/new.lua', 'hello\n')
  git({ 'add', 'new.lua' }, root)

  local snapshot = git_ops.index_snapshot(root, { 'new.lua' })
  local stack = {}
  git_ops.push_undo(stack, 'staged', { { type = 'reset_paths', paths = { 'new.lua' }, expected_index = snapshot } })

  -- Modify the staged content (simulates user doing git add -p or editing)
  write_file(root .. '/new.lua', 'modified\n')
  git({ 'add', 'new.lua' }, root)

  -- Undo should fail (index changed)
  git_ops.undo_last_action(stack, root, function() end)

  -- new.lua should still be staged (undo was rejected)
  local s = staged_files(root)
  local found = false
  for _, f in ipairs(s) do
    if f == 'new.lua' then found = true end
  end
  assert_truthy(found, 'expected new.lua still staged after rejected undo')
end)

run('undo add_paths succeeds when index unchanged', function(root)
  write_file(root .. '/base.txt', 'modified\n')
  git({ 'add', 'base.txt' }, root)

  -- Unstage it
  git({ 'reset', 'HEAD', '--', 'base.txt' }, root)
  local snapshot = git_ops.index_snapshot(root, { 'base.txt' })
  local stack = {}
  git_ops.push_undo(stack, 'unstaged', { { type = 'add_paths', paths = { 'base.txt' }, expected_index = snapshot } })

  -- Undo should succeed: re-stage base.txt
  git_ops.undo_last_action(stack, root, function() end)

  local s = staged_files(root)
  local found = false
  for _, f in ipairs(s) do
    if f == 'base.txt' then found = true end
  end
  assert_truthy(found, 'expected base.txt re-staged after undo')
end)

run('undo add_paths fails when index changed', function(root)
  write_file(root .. '/base.txt', 'modified\n')
  git({ 'add', 'base.txt' }, root)
  git({ 'reset', 'HEAD', '--', 'base.txt' }, root)

  local snapshot = git_ops.index_snapshot(root, { 'base.txt' })
  local stack = {}
  git_ops.push_undo(stack, 'unstaged', { { type = 'add_paths', paths = { 'base.txt' }, expected_index = snapshot } })

  -- Change the file and stage something else to alter the index
  write_file(root .. '/base.txt', 'changed again\n')
  git({ 'add', 'base.txt' }, root)

  -- Undo should fail
  git_ops.undo_last_action(stack, root, function() end)

  -- base.txt should remain staged with new content (undo rejected)
  local content = git({ 'show', ':base.txt' }, root)
  assert_eq(content, 'changed again', 'expected new staged content preserved')
end)

-- ============================================================================
-- group: restore_blobs undo (discard file)
-- ============================================================================

io.write(color.cyan .. 'restore_blobs undo' .. color.reset .. '\n')

run('undo discard restores file content', function(root)
  write_file(root .. '/base.txt', 'user edits\n')

  -- Hash the file before discard
  local blob = git_ops.hash_file(root .. '/base.txt', true, root)
  assert_truthy(blob, 'expected blob hash')

  -- Discard (checkout from index)
  git({ 'checkout', '--', 'base.txt' }, root)
  local expected_blob = git_ops.hash_file(root .. '/base.txt', false, root)

  local stack = {}
  git_ops.push_undo(stack, 'reverted', {
    { type = 'restore_blobs', files = { { path = 'base.txt', blob = blob, expected_blob = expected_blob } } }
  })

  -- Undo: restore original content
  git_ops.undo_last_action(stack, root, function() end)

  local content = read_file(root .. '/base.txt')
  assert_eq(content, 'user edits\n', 'expected original content restored')
end)

run('undo discard fails if file was modified after discard', function(root)
  write_file(root .. '/base.txt', 'user edits\n')
  local blob = git_ops.hash_file(root .. '/base.txt', true, root)
  git({ 'checkout', '--', 'base.txt' }, root)
  local expected_blob = git_ops.hash_file(root .. '/base.txt', false, root)

  local stack = {}
  git_ops.push_undo(stack, 'reverted', {
    { type = 'restore_blobs', files = { { path = 'base.txt', blob = blob, expected_blob = expected_blob } } }
  })

  -- Someone modifies the file after discard
  write_file(root .. '/base.txt', 'someone else changed\n')

  -- Undo should fail (expected_blob mismatch)
  git_ops.undo_last_action(stack, root, function() end)

  -- File should keep the "someone else" content
  local content = read_file(root .. '/base.txt')
  assert_eq(content, 'someone else changed\n', 'file should not be overwritten')
end)

run('undo untracked delete restores file', function(root)
  write_file(root .. '/untracked.txt', 'new file\n')
  local blob = git_ops.hash_file(root .. '/untracked.txt', true, root)
  os.remove(root .. '/untracked.txt')

  local stack = {}
  git_ops.push_undo(stack, 'removed untracked', {
    { type = 'restore_blobs', files = { { path = 'untracked.txt', blob = blob, expected_absent = true } } }
  })

  git_ops.undo_last_action(stack, root, function() end)

  assert_truthy(file_exists(root .. '/untracked.txt'), 'file should be restored')
  assert_eq(read_file(root .. '/untracked.txt'), 'new file\n')
end)

run('undo untracked delete fails if file reappeared', function(root)
  write_file(root .. '/untracked.txt', 'new file\n')
  local blob = git_ops.hash_file(root .. '/untracked.txt', true, root)
  os.remove(root .. '/untracked.txt')

  local stack = {}
  git_ops.push_undo(stack, 'removed untracked', {
    { type = 'restore_blobs', files = { { path = 'untracked.txt', blob = blob, expected_absent = true } } }
  })

  -- File reappears before undo
  write_file(root .. '/untracked.txt', 'different content\n')

  git_ops.undo_last_action(stack, root, function() end)

  -- Should not overwrite the reappeared file
  assert_eq(read_file(root .. '/untracked.txt'), 'different content\n')
end)

-- ============================================================================
-- group: index_snapshot
-- ============================================================================

io.write(color.cyan .. 'index_snapshot' .. color.reset .. '\n')

run('index_snapshot returns consistent output for same state', function(root)
  write_file(root .. '/base.txt', 'modified\n')
  git({ 'add', 'base.txt' }, root)

  local s1 = git_ops.index_snapshot(root, { 'base.txt' })
  local s2 = git_ops.index_snapshot(root, { 'base.txt' })
  assert_eq(s1, s2, 'same state should produce same snapshot')
end)

run('index_snapshot changes after modifying staged content', function(root)
  write_file(root .. '/base.txt', 'v1\n')
  git({ 'add', 'base.txt' }, root)
  local s1 = git_ops.index_snapshot(root, { 'base.txt' })

  write_file(root .. '/base.txt', 'v2\n')
  git({ 'add', 'base.txt' }, root)
  local s2 = git_ops.index_snapshot(root, { 'base.txt' })

  assert_truthy(s1 ~= s2, 'different staged content should produce different snapshot')
end)

-- ============================================================================
-- group: undo works when cwd differs from git root
-- ============================================================================

io.write(color.cyan .. 'undo with different cwd' .. color.reset .. '\n')

run('undo reset_paths works from subdirectory', function(root)
  vim.fn.mkdir(root .. '/sub', 'p')
  write_file(root .. '/sub/file.lua', 'content\n')
  git({ 'add', 'sub/file.lua' }, root)

  local snapshot = git_ops.index_snapshot(root, { 'sub/file.lua' })
  local stack = {}
  git_ops.push_undo(stack, 'staged', { { type = 'reset_paths', paths = { 'sub/file.lua' }, expected_index = snapshot } })

  -- Undo from git root (not from sub/) — should still work
  git_ops.undo_last_action(stack, root, function() end)

  local s = status_short(root)
  assert_truthy(s:find('%?%? sub/'), 'expected sub/ untracked after undo from root')
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
