-- Diff target resolution and independent context/layout keymaps.
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

local fixture = vim.fn.tempname() .. '-diff-preview'
local previous_cwd = vim.fn.getcwd()
local env_keeper = require('lu5je0.misc.env-keeper')
local original_get, original_set = env_keeper.get, env_keeper.set
local original_system, original_readfile = vim.system, vim.fn.readfile
local fetch_count = 0
vim.system = function(...)
  fetch_count = fetch_count + 1
  return original_system(...)
end
vim.fn.readfile = function(...)
  fetch_count = fetch_count + 1
  return original_readfile(...)
end
local state = require('lu5je0.ext.sidebar.state')

r.run('c and d preserve all four combinations in the Changes list and diff panes', function()
  vim.fn.mkdir(fixture, 'p')
  local function git(args)
    local command = { 'git', '-C', fixture }
    vim.list_extend(command, args)
    local result = vim.system(command, { text = true }):wait()
    assert(result.code == 0, result.stderr)
  end
  git { 'init', '-q' }
  local lines = {}
  for i = 1, 40 do
    lines[i] = 'context-' .. i
  end
  vim.fn.writefile(lines, fixture .. '/demo.txt')
  git { 'add', 'demo.txt' }
  git { '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'base' }
  lines[20] = 'changed'
  vim.fn.writefile(lines, fixture .. '/demo.txt')
  vim.cmd.cd(fixture)
  local prefs = { sidebar_diff_mode = 'single', sidebar_diff_changes_only = false }
  env_keeper.get = function(key, default)
    if prefs[key] ~= nil then
      return prefs[key]
    end
    return default
  end
  env_keeper.set = function(key, value)
    prefs[key] = value
  end

  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { 'demo.txt' })
  state.active_tab_idx = require('lu5je0.ext.sidebar.config').tab_idx('git_changes')
  state.git_changes.display_items = { make_item('unstaged', ' M', 'demo.txt') }
  local keymaps = require('lu5je0.ext.sidebar.keymaps')
  local config = require('lu5je0.ext.sidebar.config')
  state.active_tab_idx = config.tab_idx('files')
  keymaps.apply_for_tab(state.active_tab_idx)
  r.assert_eq(vim.fn.maparg('dd', 'n', false, true).buffer, 1)
  r.assert_eq(vim.fn.maparg('d', 'n'), '')
  state.active_tab_idx = config.tab_idx('git_changes')
  keymaps.apply_for_tab(state.active_tab_idx)
  r.assert_eq(vim.fn.maparg('dd', 'n'), '', 'Files cut mapping must not leak into Changes')
  r.assert_eq(vim.fn.maparg('cd', 'n'), '', 'Files cd mapping must not delay c in Changes')
  r.assert_eq(vim.fn.maparg('d', 'n', false, true).nowait, 1)
  r.assert_eq(vim.fn.maparg('c', 'n', false, true).nowait, 1)
  local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
  end
  local function ready(mode, compact)
    assert(
      vim.wait(3000, function()
        local d = state.diff_preview
        if mode == 'single' then
          if not d.win_single or not vim.api.nvim_win_is_valid(d.win_single) then
            return false
          end
          local text = table.concat(vim.api.nvim_buf_get_lines(d.buf_single, 0, -1, false), '\n')
          return text:find('+changed', 1, true) ~= nil and (text:find('context-40', 1, true) == nil) == compact
        end
        return d.win_left
          and d.win_right
          and vim.api.nvim_win_is_valid(d.win_left)
          and vim.api.nvim_win_is_valid(d.win_right)
          and vim.wo[d.win_left].diff
          and vim.wo[d.win_right].diff
          and vim.wo[d.win_left].foldenable == compact
          and vim.wo[d.win_right].foldenable == compact
      end, 10),
      'preview did not reach ' .. mode .. ', changes only=' .. tostring(compact)
    )
    r.assert_eq(prefs.sidebar_diff_mode, mode)
    r.assert_eq(prefs.sidebar_diff_changes_only, compact)
    for _, buf in ipairs { state.buf, state.diff_preview.buf_single or state.diff_preview.buf_left, state.diff_preview.buf_right } do
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
        assert(map.lhs ~= 'D' and map.lhs ~= 'gd', 'obsolete diff mapping: ' .. map.lhs)
      end
    end
  end

  feed('<Space>')
  ready('single', false)
  local initial_fetch_count = fetch_count
  for _, expected in ipairs {
    { 'c', 'single', true },
    { 'd', 'dual', true },
    { 'c', 'dual', false },
    { 'd', 'single', false },
  } do
    feed(expected[1])
    ready(expected[2], expected[3])
    r.assert_eq(fetch_count, initial_fetch_count, 'list toggles must reuse the loaded diff')
    r.assert_truthy(require('lu5je0.ext.sidebar.actions.preview').is_active(), 'switching must keep Space preview active')
    r.assert_eq(vim.api.nvim_get_current_win(), state.win)
  end
  r.assert_truthy(require('lu5je0.ext.sidebar.actions.preview').is_active(), 'rebuild must keep list preview active')
  r.assert_eq(vim.api.nvim_get_current_win(), state.win)
  feed('<Space>')
  for _, expected in ipairs {
    { 'c', 'single', true },
    { 'd', 'dual', true },
    { 'c', 'dual', false },
    { 'd', 'single', false },
  } do
    feed(expected[1])
    ready(expected[2], expected[3])
    r.assert_eq(fetch_count, initial_fetch_count, 'pane toggles must reuse the loaded diff')
    local d = state.diff_preview
    r.assert_eq(vim.api.nvim_get_current_win(), d.win_single or d.win_left, 'switching must keep focus in the diff')
  end
  feed('d')
  ready('dual', false)
  feed('<C-l>')
  r.assert_eq(vim.api.nvim_get_current_win(), state.diff_preview.win_right)
  feed('d')
  ready('single', false)
  r.assert_eq(vim.api.nvim_get_current_win(), state.diff_preview.win_single)
  r.assert_eq(fetch_count, initial_fetch_count, 'switching from the right pane must reuse the loaded diff')
  vim.api.nvim_set_current_win(state.win)
  feed('d')
  ready('dual', false)
  r.assert_eq(vim.api.nvim_get_current_win(), state.win, 'returning to the list must keep layout switching available')
  r.assert_eq(fetch_count, initial_fetch_count, 'returning to the list must reuse the loaded diff')
  vim.api.nvim_set_current_win(state.diff_preview.win_left)
  local function close_preview()
    feed('q')
    assert(
      vim.wait(1000, function()
        local d = state.diff_preview
        return d.win_single == nil and d.win_left == nil and d.win_right == nil
      end, 10),
      'q must close all preview windows'
    )
    r.assert_eq(vim.api.nvim_get_current_win(), state.win)
    r.assert_eq(require('lu5je0.ext.sidebar.actions.preview').is_active(), false)
    r.assert_eq(diff_preview.refresh(), false, 'closed previews must release the cached refresh')
  end
  close_preview()
  feed('<Space>')
  ready('dual', false)
  feed('<Space>')
  close_preview()
end)

local child
r.run('real d and c input does not wait for Files mappings or timeoutlen', function()
  child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n' }, { rpc = true })
  assert(child > 0, 'failed to start isolated Neovim')
  vim.rpcrequest(child, 'nvim_exec_lua', [[
    vim.opt.runtimepath:prepend(...)
    vim.o.timeoutlen = 2000
    vim.notify = function() end
    local state = require('lu5je0.ext.sidebar.state')
    local config = require('lu5je0.ext.sidebar.config')
    local keymaps = require('lu5je0.ext.sidebar.keymaps')
    local keeper = require('lu5je0.misc.env-keeper')
    keeper.get = function(_, default) return default end
    keeper.set = function(key) vim.g.last_toggle = key end
    state.buf = vim.api.nvim_get_current_buf()
    state.active_tab_idx = config.tab_idx('files')
    keymaps.apply_for_tab(state.active_tab_idx)
    state.active_tab_idx = config.tab_idx('git_changes')
    keymaps.apply_for_tab(state.active_tab_idx)
  ]], { repo_root .. '/vim' })
  for _, input in ipairs { { 'd', 'sidebar_diff_mode' }, { 'c', 'sidebar_diff_changes_only' } } do
    vim.rpcrequest(child, 'nvim_input', input[1])
    r.assert_truthy(vim.wait(500, function()
      return vim.rpcrequest(child, 'nvim_eval', 'get(g:, "last_toggle", "")') == input[2]
    end, 10), input[1] .. ' must execute before timeoutlen')
  end
  vim.rpcrequest(child, 'nvim_exec_lua', [[
    local state = require('lu5je0.ext.sidebar.state')
    state.active_tab_idx = require('lu5je0.ext.sidebar.config').tab_idx('files')
    require('lu5je0.ext.sidebar.keymaps').apply_for_tab(state.active_tab_idx)
    assert(vim.fn.maparg('dd', 'n', false, true).buffer == 1, 'Files must restore dd')
    assert(vim.fn.maparg('d', 'n') == '', 'Changes d must be removed from Files')
    assert(vim.fn.maparg('c', 'n') == '', 'Changes c must be removed from Files')
  ]], {})
end)
if child and child > 0 then
  vim.fn.jobstop(child)
end

require('lu5je0.ext.sidebar.actions.preview').stop()
env_keeper.get, env_keeper.set = original_get, original_set
vim.system, vim.fn.readfile = original_system, original_readfile
vim.cmd.cd(previous_cwd)
vim.fn.delete(fixture, 'rf')
r.finish()
