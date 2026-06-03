-- Tree-sidebar interactive tests.
-- Spins up real buffer + window, real fixture directories, real cwd switches.
-- vim.system is mocked because git is async and we already cover its parser
-- in spec.lua; this file targets state-machine behaviour only.
--
-- Usage: cd vim && nvim --headless -u NONE -l tests/tree-sidebar/interactive_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local files = require('lu5je0.ext.tree-sidebar.sources.files')
local sidebar = require('lu5je0.ext.tree-sidebar.init')
local state = require('lu5je0.ext.tree-sidebar.state')
local config = require('lu5je0.ext.tree-sidebar.config')
local navigation = require('lu5je0.ext.tree-sidebar.actions.navigation')

for _, hl in ipairs(config.highlights) do
  vim.api.nvim_set_hl(0, hl[1], hl[2])
end

local _aug = vim.api.nvim_create_augroup('TreeSidebarTest', { clear = true })
vim.api.nvim_create_autocmd('DirChanged', {
  group = _aug,
  callback = sidebar._on_dir_changed,
})

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
  if actual ~= expected then
    error(string.format('%s\n      actual:   %s\n      expected: %s',
      msg or 'mismatch', dump(actual), dump(expected)), 2)
  end
end

local function assert_truthy(v, msg)
  if not v then error(msg or 'expected truthy, got nil/false', 2) end
end

-- ============================================================================
-- fixture helpers
-- ============================================================================

local function realpath(p)
  return vim.fn.resolve(vim.fn.fnamemodify(p, ':p')):gsub('/+$', '')
end

local function mkdir(path)
  assert(vim.fn.mkdir(path, 'p') == 1, 'mkdir failed: ' .. path)
end

local function touch(path)
  local fd = assert(io.open(path, 'w'))
  fd:close()
end

-- Build: <root>/{alpha/{a.txt}, beta/{b.txt}, top.txt}
local function make_fixture()
  local root = realpath(vim.fn.tempname() .. '-tsbar')
  mkdir(root .. '/alpha')
  mkdir(root .. '/beta')
  touch(root .. '/alpha/a.txt')
  touch(root .. '/beta/b.txt')
  touch(root .. '/top.txt')
  return root
end

local function rmrf(path)
  if path and path ~= '' and path:match('/tmp/') then
    vim.fn.delete(path, 'rf')
  end
end

-- ============================================================================
-- environment setup/teardown
-- ============================================================================

local _orig_vim_system = vim.system
local _system_calls = {}
local _system_stdout = ''

local function install_system_mock()
  _system_calls = {}
  vim.system = function(cmd, opts, cb)
    _system_calls[#_system_calls + 1] = cmd
    if cb then
      vim.schedule(function()
        cb({ code = 0, stdout = _system_stdout, stderr = '' })
      end)
    end
    return { wait = function() return { code = 0, stdout = _system_stdout, stderr = '' } end }
  end
end

local function restore_system()
  vim.system = _orig_vim_system
end

local function reset_state()
  -- per-tab state via metatable; clear current tab's entries
  state.files.root = nil
  state.files._root_cache = {}
  state.files._cursor_cache = {}
  state.files.git_status_map = {}
  state.files.display_items = {}
  state.files.hide_dotfiles = true
  state.active_tab_idx = config.tab_idx('files')
  -- global
  state._is_jumping = false
  state._last_pushed_cwd = nil
  state.pwd_stack = require('lu5je0.lang.stack'):create()
  state.pwd_forward_stack = require('lu5je0.lang.stack'):create()
end

local function open_fake_sidebar()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor', row = 0, col = 0, width = 30, height = 20,
    style = 'minimal', focusable = false,
  })
  state.buf = buf
  state.win = win
  return buf, win
end

local function close_fake_sidebar()
  files.stop_watchers()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
end

local _initial_cwd = vim.fn.getcwd()

local function with_fixture(fn)
  local fixture = make_fixture()
  reset_state()
  install_system_mock()
  vim.cmd('cd ' .. vim.fn.fnameescape(fixture))
  open_fake_sidebar()

  local ok, err = pcall(fn, fixture)

  close_fake_sidebar()
  vim.cmd('cd ' .. vim.fn.fnameescape(_initial_cwd))
  restore_system()
  rmrf(fixture)
  if not ok then error(err, 0) end
end

local function run(name, fn)
  io.write('  ' .. name .. ' ... ')
  local ok, err = pcall(with_fixture, fn)
  if ok then
    io.write(color.green .. 'PASS' .. color.reset .. '\n')
    passed = passed + 1
  else
    io.write(color.red .. 'FAIL' .. color.reset .. '\n    ' .. tostring(err) .. '\n')
    failed = failed + 1
  end
end

-- ============================================================================
-- group: cd_to_node / cd_parent / cd_home
-- ============================================================================

io.write(color.cyan .. 'cd actions' .. color.reset .. '\n')

run('cd_to_node enters dir, stashes old root in cache, resets cursor', function(fixture)
  files.render() -- builds root for fixture
  local original_root = state.files.root
  assert_eq(state.files.root.abs_path, fixture)

  -- find display item for "alpha" and put cursor on it
  local target_line
  for i, item in ipairs(state.files.display_items) do
    if item.type == 'dir' and item.node.name == 'alpha' then
      target_line = i
      break
    end
  end
  assert_truthy(target_line, 'alpha not found in display_items')
  vim.api.nvim_win_set_cursor(state.win, { target_line, 0 })

  files.cd_to_node()

  assert_eq(realpath(vim.fn.getcwd()), fixture .. '/alpha')
  -- DirChanged autocmd ran: root replaced
  assert_truthy(state.files.root, 'expected root to exist after DirChanged')
  assert_eq(state.files.root.abs_path, fixture .. '/alpha')
  -- old root cached under old cwd
  assert_eq(state.files._root_cache[fixture], original_root)
  -- cursor reset to top
  local cur = vim.api.nvim_win_get_cursor(state.win)
  assert_eq(cur[1], 1)
end)

run('cd_parent stashes current root, navigates up', function(fixture)
  vim.cmd('cd ' .. vim.fn.fnameescape(fixture .. '/alpha'))
  reset_state() -- clear pwd_stack/_root_cache after the explicit cd
  files.render()
  local sub_root = state.files.root
  assert_eq(sub_root.abs_path, fixture .. '/alpha')

  files.cd_parent()

  assert_eq(realpath(vim.fn.getcwd()), fixture)
  assert_eq(state.files._root_cache[fixture .. '/alpha'], sub_root)
  assert_eq(state.files.root.abs_path, fixture)
end)

run('cd_to_node restores cached root when re-entering a known dir', function(fixture)
  files.render()
  -- enter alpha
  for i, item in ipairs(state.files.display_items) do
    if item.type == 'dir' and item.node.name == 'alpha' then
      vim.api.nvim_win_set_cursor(state.win, { i, 0 })
      break
    end
  end
  files.cd_to_node()
  local alpha_root = state.files.root
  -- cd back up
  files.cd_parent()
  -- enter alpha again — should be the same cached root object
  for i, item in ipairs(state.files.display_items) do
    if item.type == 'dir' and item.node.name == 'alpha' then
      vim.api.nvim_win_set_cursor(state.win, { i, 0 })
      break
    end
  end
  files.cd_to_node()
  assert_eq(state.files.root, alpha_root)
end)

-- ============================================================================
-- group: DirChanged autocmd handler
-- ============================================================================

io.write(color.cyan .. 'DirChanged handler' .. color.reset .. '\n')

run('external :cd swaps root and clears stale git_status_map', function(fixture)
  files.render()
  state.files.git_status_map = { ['stale.txt'] = { hl = 'X', glyph = 'x', xy = '??' } }
  local original_root = state.files.root

  vim.cmd('cd ' .. vim.fn.fnameescape(fixture .. '/beta'))
  -- DirChanged autocmd fires synchronously via :cd; verify outcome
  assert_eq(realpath(vim.fn.getcwd()), fixture .. '/beta')
  assert_eq(state.files._root_cache[fixture], original_root)
  assert_eq(state.files.root.abs_path, fixture .. '/beta')
  -- stale entry must be gone
  assert_eq(state.files.git_status_map['stale.txt'], nil)
end)

run('window-scope DirChanged is ignored (root unchanged)', function(fixture)
  files.render()
  local original_root = state.files.root
  -- Simulate by calling _on_dir_changed directly with scope=window, since
  -- triggering :lcd from a fake floating window would also fire scope=window
  -- but with a real cwd flip we'd lose the assertion target.
  sidebar._on_dir_changed({ match = 'window' })
  assert_eq(state.files.root, original_root)
end)

run('autocmd no-op when new_cwd matches current root abs_path', function(fixture)
  files.render()
  local original_root = state.files.root
  -- Manually invoke handler with a tabpage-scope event but cwd unchanged
  sidebar._on_dir_changed({ match = 'global' })
  assert_eq(state.files.root, original_root)
  -- No spurious cache writes for the same cwd
  assert_eq(state.files._root_cache[fixture], nil)
end)

-- ============================================================================
-- group: back / forward
-- ============================================================================

io.write(color.cyan .. 'back / forward' .. color.reset .. '\n')

run('back pops to previous cwd, forward re-enters', function(fixture)
  files.render()
  -- step into alpha via :cd (DirChanged pushes onto pwd_stack)
  state.pwd_stack:push(fixture) -- seed pwd_stack with current cwd
  state._last_pushed_cwd = fixture
  vim.cmd('cd ' .. vim.fn.fnameescape(fixture .. '/alpha'))
  assert_truthy(state.pwd_stack:count() >= 2, 'expected stack to grow after :cd')

  navigation.back()
  assert_eq(realpath(vim.fn.getcwd()), fixture)
  assert_truthy(state.pwd_forward_stack:count() >= 1, 'expected forward stack to grow on back')

  navigation.forward()
  assert_eq(realpath(vim.fn.getcwd()), fixture .. '/alpha')
  assert_eq(state.pwd_forward_stack:count(), 0)
end)

run('back is a no-op when stack has only the initial cwd', function(fixture)
  files.render()
  state.pwd_stack:push(fixture)
  state._last_pushed_cwd = fixture
  navigation.back()
  assert_eq(realpath(vim.fn.getcwd()), fixture)
end)

-- ============================================================================
-- summary
-- ============================================================================

io.write(string.format('\n%s passed, %s failed\n',
  color.green .. tostring(passed) .. color.reset,
  (failed > 0 and color.red or color.green) .. tostring(failed) .. color.reset))

if failed > 0 then os.exit(1) end
