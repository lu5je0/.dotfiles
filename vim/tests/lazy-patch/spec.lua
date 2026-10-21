-- Run with nvim --headless -u NONE -i NONE -n -l vim/tests/lazy-patch/spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
local tmp = vim.fn.tempname()
local lazy = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
assert(vim.uv.fs_stat(lazy .. '/lua/lazy/init.lua'), 'lazy.nvim is not installed')

local function write(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local file = assert(io.open(path, 'wb'))
  assert(file:write(content))
  file:close()
end

local function git(repo, ...)
  local result = vim.system({ 'git', '-C', repo, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

local function patch(path, before, after)
  return ('--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n-%s\n+%s\n'):format(path, path, before, after)
end

local config = tmp .. '/config/nvim'
local repo = tmp .. '/custom-plugin-directory'
local nested = tmp .. '/nested-directory'
local initial_value = "return 'upstream'"
local changed_value = "return 'updated upstream'"
local init_source = "local value = require('fixture.value'); return { value = value, original = require('fixture.original'), source = function() end }"
local patched_init = init_source:gsub('value = value,', 'value = value, patched = true,')
local init_patch = patch('lua/fixture/init.lua', init_source, patched_init)
local function value_patch(before, after)
  return init_patch .. patch('lua/fixture/value.lua', before, ("return '%s'"):format(after))
end

local child = [=[
local base, lazy, root = vim.env.PATCH_TEST_BASE, vim.env.PATCH_TEST_LAZY, vim.env.PATCH_TEST_ROOT
vim.o.loadplugins = true
vim.loader.enable()
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(lazy)
local apply_count, git_count = 0, 0
local system = vim.system
vim.system = function(cmd, opts, cb)
  if cmd[1] == 'git' then
    git_count = git_count + 1
    assert(cmd[2] == 'apply', 'unexpected Git command: ' .. vim.inspect(cmd))
    apply_count = apply_count + 1
  end
  return system(cmd, opts, cb)
end
require('lu5je0.ext.lazy_patch').setup()
local configured = 0
require('lazy').setup({
  {
    dir = base .. '/custom-plugin-directory', name = 'renamed-fixture', lazy = true,
    patches = { 'fixture.diff' },
    config = function()
      configured = configured + 1
      assert(require('fixture').patched)
    end,
  },
  {
    {
      dir = base .. '/nested-directory', name = 'nested-fixture', lazy = true,
      patches = 'nested.diff', cmd = 'NestedFixture',
      config = function()
        assert(require('nested') == 'patched nested')
        vim.api.nvim_create_user_command('NestedFixture', function() end, {})
      end,
    },
    { dir = base .. '/disabled', enabled = false, patches = 'missing.diff' },
  },
}, {
  root = base .. '/data/nvim/lazy', lockfile = base .. '/lazy-lock.json',
  install = { missing = false }, checker = { enabled = false },
  change_detection = { enabled = false }, pkg = { enabled = false },
  rocks = { enabled = false }, readme = { enabled = false },
})
assert(configured == 0 and not package.loaded.fixture and not package.loaded.nested, 'patch registration broke lazy loading')
assert(git_count == 0, 'registration spawned Git')
local hooks = vim.api.nvim_get_autocmds({ group = 'LazyPatchCache' })
assert(#hooks == 1 and hooks[1].pattern == 'LazyPlugins', 'unexpected patch lifecycle hooks')

if vim.env.PATCH_TEST_FAILURE == '1' then
  local ok, err = pcall(require, 'fixture')
  assert(not ok and tostring(err):find("Failed to apply patch 'fixture.diff'", 1, true), tostring(err))
  assert(configured == 0, 'conflicting patch fell back to original code')
  assert(#vim.fn.glob(vim.fn.stdpath('cache') .. '/lazy-patches/.build-*', false, true) == 0, 'failed build was not cleaned up')
  print('PASS conflicting patch fails without loading original module')
  vim.cmd('qa!')
  return
end

local fixture = require('fixture')
assert(fixture.patched and fixture.value == vim.env.PATCH_TEST_VALUE, vim.inspect(fixture))
assert(fixture.original == 'untouched', 'unpatched dependency did not load')
assert(configured == 1, 'require-triggered config did not execute exactly once: ' .. configured)
local source = debug.getinfo(fixture.source, 'S').source
assert(source:find(vim.fn.stdpath('cache') .. '/lazy-patches/', 1, true), source)
vim.cmd('NestedFixture')
assert(package.loaded.nested == 'patched nested', 'command-triggered nested plugin was not patched')
assert(require('fixture') == fixture, 'require lost its module cache')
for _, event in ipairs({ 'LazyUpdatePre', 'LazyUpdate', 'LazyCheckPre', 'LazyCheck', 'LazySyncPre', 'LazySync' }) do
  vim.api.nvim_exec_autocmds('User', { pattern = event, modeline = false })
end
assert(apply_count == tonumber(vim.env.PATCH_TEST_APPLIES), ('expected %s applies, got %d'):format(vim.env.PATCH_TEST_APPLIES, apply_count))
local previous = apply_count
vim.cmd('LazyApplyPatch')
assert(apply_count == previous, 'explicit command reapplied a valid cached patch')
print(('PASS %s: %d Git calls, lazy require/config and command paths patched'):format(vim.env.PATCH_TEST_PHASE, git_count))
vim.cmd('qa!')
]=]

local function run(phase, value, applies, failure)
  local result = vim
    .system({ vim.v.progpath, '--headless', '-u', 'NONE', '-i', 'NONE', '-n', '-l', tmp .. '/child.lua' }, {
      text = true,
      env = {
        XDG_CONFIG_HOME = tmp .. '/config',
        XDG_CACHE_HOME = tmp .. '/cache',
        XDG_DATA_HOME = tmp .. '/data',
        XDG_STATE_HOME = tmp .. '/state',
        PATCH_TEST_BASE = tmp,
        PATCH_TEST_LAZY = lazy,
        PATCH_TEST_ROOT = root,
        PATCH_TEST_PHASE = phase,
        PATCH_TEST_VALUE = value,
        PATCH_TEST_APPLIES = tostring(applies),
        PATCH_TEST_FAILURE = failure and '1' or '0',
      },
    })
    :wait()
  assert(result.code == 0, phase .. '\n' .. result.stdout .. result.stderr)
  print(vim.trim(result.stdout .. result.stderr))
  assert(git(repo, 'status', '--porcelain') == '', 'plugin files were modified')
  assert(git(nested, 'status', '--porcelain') == '', 'nested plugin files were modified')
end

local ok, err = pcall(function()
  write(tmp .. '/child.lua', child)
  write(repo .. '/lua/fixture/init.lua', init_source .. '\n')
  write(repo .. '/lua/fixture/value.lua', initial_value .. '\n')
  write(repo .. '/lua/fixture/original.lua', "return 'untouched'\n")
  write(nested .. '/lua/nested.lua', "return 'upstream nested'\n")
  for _, dir in ipairs { repo, nested } do
    git(dir, 'init', '-q')
    git(dir, 'add', '.')
    git(dir, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture')
  end
  local original_commit = git(repo, 'rev-parse', 'HEAD')
  write(config .. '/patches/fixture.diff', value_patch(initial_value, 'patched'))
  write(config .. '/patches/nested.diff', patch('lua/nested.lua', "return 'upstream nested'", "return 'patched nested'"))
  run('cold cache', 'patched', 2)
  run('warm cache', 'patched', 0)
  write(config .. '/patches/fixture.diff', value_patch(initial_value, 'revised patch'))
  run('patch changed', 'revised patch', 1)
  write(repo .. '/lua/fixture/value.lua', changed_value .. '\n')
  git(repo, 'add', '.')
  git(repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'upstream update')
  run('upstream conflicts with old patch', 'revised patch', 0, true)
  write(config .. '/patches/fixture.diff', value_patch(changed_value, 'updated patch'))
  run('upstream and patch changed', 'updated patch', 1)
  git(repo, 'checkout', '-q', original_commit)
  write(config .. '/patches/fixture.diff', value_patch(initial_value, 'patched'))
  run('restored upstream reuses cache', 'patched', 0)
end)
vim.fn.delete(tmp, 'rf')
assert(ok, err)
