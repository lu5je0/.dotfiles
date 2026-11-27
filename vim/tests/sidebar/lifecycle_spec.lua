-- Source transitions and delayed callbacks with real sidebar buffers/windows.
-- Usage: cd vim && nvim --headless -u NONE -i NONE -n -l tests/sidebar/lifecycle_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(root .. '/vim')
local h = dofile(root .. '/vim/tests/sidebar/helpers.lua')
local r = h.make_runner()
package.loaded['lu5je0.misc.env-keeper'] = {
  get = function(_, default)
    return default
  end,
  set = function() end,
}

local pending, requests = {}, {}
local copied_text
package.loaded['lu5je0.core.clipboard'] = { set = function(value) copied_text = value end }
local original_system = vim.system
vim.system = function(args, opts, callback)
  local task = { args = args, opts = opts, callback = callback, killed = false }
  local job = {
    kill = function()
      task.killed = true
    end,
  }
  if args[2] == 'stash' then
    pending[#pending + 1] = task
  else
    vim.schedule(function()
      callback { code = 0, stdout = '', stderr = '' }
    end)
  end
  return job
end
local original_clients, original_request = vim.lsp.get_clients, vim.lsp.buf_request
vim.lsp.get_clients = function()
  return { { server_capabilities = { documentSymbolProvider = true } } }
end
vim.lsp.buf_request = function(buf, _, _, callback)
  local request = { buf = buf, callback = callback, cancelled = false }
  requests[#requests + 1] = request
  return {}, function()
    request.cancelled = true
  end
end

local state = require('lu5je0.ext.sidebar.state')
local config = require('lu5je0.ext.sidebar.config')
local sidebar = require('lu5je0.ext.sidebar')
local lifecycle = require('lu5je0.ext.sidebar.lifecycle')
local symbols = require('lu5je0.ext.sidebar.sources.symbols')
sidebar.setup()
local initial_tab = vim.api.nvim_get_current_tabpage()
local fixture = vim.fn.tempname() .. '-lifecycle'
vim.fn.mkdir(fixture .. '/.git', 'p')
vim.fn.writefile({ 'one', 'two', 'three' }, fixture .. '/demo.txt')

local function drain()
  vim.wait(80, function()
    return false
  end, 5)
end
local function text()
  return vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
end
local function open(id, opts)
  sidebar.open_tab(config.tab_idx(id), vim.tbl_extend('force', { no_toggle = true }, opts or {}))
end
local function result(name)
  return { { name = name, kind = 12, range = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 0 } } } }
end
local function run(name, fn)
  r.run(name, function()
    vim.cmd('tabnew')
    vim.cmd.tcd(fixture)
    vim.cmd.edit(fixture .. '/demo.txt')
    local source_win = vim.api.nvim_get_current_win()
    pending, requests = {}, {}
    fn(source_win)
  end)
  vim.api.nvim_set_current_tabpage(initial_tab)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab ~= initial_tab then
      vim.cmd('tabclose! ' .. vim.api.nvim_tabpage_get_number(tab))
    end
  end
  drain()
end

r.group('source lifecycle')

run('Symbols uses the shared fold keys and keeps them scoped to tree tabs', function(source_win)
  open('symbols', { source_win = source_win })
  local function node(name, children)
    local symbol = result(name)[1]
    symbol.children = children
    return symbol
  end
  requests[#requests].callback(nil, {
    node('branch', { node('nested', { node('leaf') }) }),
    node('other', { node('sibling') }),
  })
  drain()
  local function names()
    return vim.tbl_map(function(item) return item.node.name end, state.symbols.display_items)
  end
  vim.cmd('normal ggzRzC')
  r.assert_eq(names(), { 'branch', 'other', 'sibling' })
  r.assert_eq(vim.fn.line('.'), 1)
  vim.cmd('normal zozo')
  r.assert_eq(names(), { 'branch', 'nested', 'other', 'sibling' })
  vim.cmd('normal zO2jzozO')
  r.assert_eq(vim.api.nvim_get_current_win(), state.win)
  r.assert_eq(names(), { 'branch', 'nested', 'leaf', 'other', 'sibling' })
  vim.cmd('normal zC')
  r.assert_eq(names(), { 'branch', 'nested', 'other', 'sibling' })
  r.assert_eq(vim.fn.line('.'), 2)
  vim.cmd('normal zM')
  r.assert_eq(names(), { 'branch', 'other' })
  open('buffers')
  for _, key in ipairs { 'zo', 'zc', 'zO', 'zC', 'zR', 'zM' } do
    r.assert_eq(vim.fn.maparg(key, 'n'), '')
  end
end)

run('source locate dispatch preserves Files, Buffers and Symbols targets', function(source_win)
  sidebar.locate_in_tab(config.tab_idx('files'))
  r.assert_eq(state.files.display_items[vim.api.nvim_win_get_cursor(state.win)[1]].node.abs_path, fixture .. '/demo.txt')
  vim.api.nvim_set_current_win(source_win)
  sidebar.locate_in_tab(config.tab_idx('buffers'))
  local item = state.buffers.display_items[vim.api.nvim_win_get_cursor(state.win)[1]]
  r.assert_eq(item.node.buf, vim.api.nvim_win_get_buf(source_win))
  vim.api.nvim_set_current_win(source_win)
  sidebar.locate_in_tab(config.tab_idx('symbols'))
  requests[#requests].callback(nil, result('located'))
  drain()
  r.assert_eq(state.symbols.nodes[1].name, 'located')
end)

run('newer Symbols requests win when responses arrive in reverse order', function(source_win)
  open('symbols', { source_win = source_win })
  local older = requests[#requests]
  symbols.request_symbols { source_win = source_win }
  local newer = requests[#requests]
  r.assert_truthy(older.cancelled)
  newer.callback(nil, result('newer'))
  older.callback(nil, result('older'))
  drain()
  r.assert_eq(state.symbols.nodes[1].name, 'newer')
end)

run('Symbols → Files → Symbols rejects the previous visit response', function(source_win)
  open('symbols', { source_win = source_win })
  local older = requests[#requests]
  open('files')
  open('symbols', { source_win = source_win })
  requests[#requests].callback(nil, result('current visit'))
  older.callback(nil, result('previous visit'))
  drain()
  r.assert_truthy(older.cancelled)
  r.assert_eq(state.symbols.nodes[1].name, 'current visit')
end)

for _, cached in ipairs { false, true } do
  for _, locate in ipairs { false, true } do
    run(('Symbols entry renders %s before an LSP response (%s)'):format(cached and 'cached symbols' or 'empty state', locate and 'locate' or 'switch'), function(source_win)
      if cached then
        open('symbols', { source_win = source_win })
        requests[#requests].callback(nil, result('cached symbol'))
        drain()
      end
      open('files')
      r.assert_truthy(table.concat(text(), '\n'):find('demo.txt', 1, true))
      if locate then
        vim.api.nvim_set_current_win(source_win)
        sidebar.locate_in_tab(config.tab_idx('symbols'))
      else
        open('symbols', { source_win = source_win })
      end
      local lines = table.concat(text(), '\n')
      r.assert_truthy(not lines:find('demo.txt', 1, true), 'Symbols must synchronously replace Files content')
      r.assert_truthy(lines:find(cached and 'cached symbol' or 'No symbols', 1, true))
    end)
  end
end

run('Buffers delayed refresh cannot overwrite Files after switching', function()
  open('buffers')
  vim.api.nvim_exec_autocmds('BufAdd', { buffer = state.buf })
  open('files')
  local before = text()
  drain()
  r.assert_eq(text(), before)
end)

run('Changes pending locate cannot overwrite Files', function()
  open('git_changes')
  state.git_changes.sections = {}
  require('lu5je0.ext.sidebar.sources.git_changes').locate_first_file()
  open('files')
  local before = text()
  drain()
  r.assert_eq(text(), before)
end)

run('Changes cancels stash work and ignores its late callback after leaving', function()
  open('git_changes')
  require('lu5je0.ext.sidebar.sources.git_changes').reload_stash_list()
  local task = pending[#pending]
  r.assert_eq(task.opts.cwd, fixture)
  open('files')
  task.callback { code = 0, stdout = 'stash@{0}\0old stash\n' }
  drain()
  r.assert_truthy(task.killed)
  r.assert_eq(state.git_changes._stash_entries, nil)
end)

local function stash_row()
  vim.fn.mkdir(fixture .. '/.git/logs/refs', 'p')
  vim.fn.writefile({ 'fixture stash' }, fixture .. '/.git/logs/refs/stash')
  require('lu5je0.ext.sidebar.sources.git_changes').render()
  for line, item in ipairs(state.git_changes.display_items) do
    if item.section == 'stashes' and item._is_section then
      return line
    end
  end
  error('missing Stashes section')
end

run('Changes and Files act on the last directory in a compressed path', function()
  local rel = 'nix/nixos/pkgs/kimpanel'
  local dir = fixture .. '/' .. rel
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({}, dir .. '/default.nix')
  open('git_changes')
  drain()
  local changes = require('lu5je0.ext.sidebar.sources.git_changes')
  changes.update_sections_from_stdout(state.git_changes, ' M ' .. rel .. '/default.nix\0')
  changes.render()
  vim.api.nvim_set_current_win(state.win)
  vim.api.nvim_win_set_cursor(state.win, { 2, 0 })

  local function check_yanks()
    r.assert_truthy(vim.api.nvim_get_current_line():find(rel, 1, true))
    for _, case in ipairs({ { 'yp', dir }, { 'yP', rel }, { 'yn', 'kimpanel' } }) do
      copied_text = nil
      vim.cmd.normal(case[1])
      r.assert_eq(copied_text, case[2])
    end
  end

  check_yanks()
  vim.cmd('normal zCzO')
  check_yanks()
  state.files.compress_dirs = true
  vim.cmd.normal(vim.api.nvim_replace_termcodes('<leader>fe', true, false, true))
  r.assert_eq(state.active_tab_idx, config.tab_idx('files'))
  check_yanks()
  local files = require('lu5je0.ext.sidebar.sources.files')
  vim.api.nvim_win_set_cursor(state.win, { 1, 0 })
  files.find_file(fixture .. '/nix/nixos')
  check_yanks()
  vim.cmd('normal yy')
  r.assert_eq(state.files._clipboard.paths, { dir })
  vim.cmd('normal cd')
  r.assert_eq(vim.fn.getcwd(), dir)
end)

run('zC closes the Changes directory and descendants within its open section', function()
  open('git_changes')
  drain()
  local changes = require('lu5je0.ext.sidebar.sources.git_changes')
  local ts = state.git_changes
  changes.update_sections_from_stdout(ts, ' M a/nested/deep/f\0 M a/g\0 M b/f\0 M root\0')
  changes.render()
  vim.api.nvim_set_current_win(state.win)
  local function goto_path(path)
    for i, item in ipairs(ts.display_items) do
      if item.node.abs_path == fixture .. '/' .. path then
        vim.api.nvim_win_set_cursor(state.win, { i, 0 })
        return
      end
    end
    error('missing ' .. path)
  end
  local function current()
    return ts.display_items[vim.api.nvim_win_get_cursor(state.win)[1]]
  end

  goto_path('a/nested/deep/f')
  vim.cmd('normal zO')
  r.assert_eq(vim.api.nvim_get_current_win(), state.win)
  r.assert_eq(current().node.rel_path, 'a/nested/deep/f')
  vim.cmd('normal zC')
  r.assert_eq(current().node.name, 'nested')
  r.assert_eq(current().node.expanded, false)
  r.assert_eq(current().node.children[1].expanded, false)
  r.assert_eq(current().parent.node.name, 'a')
  r.assert_eq(current().parent.node.expanded, true)
  goto_path('a')
  vim.cmd('normal zC')
  r.assert_eq(current().node.name, 'a')
  r.assert_eq(current().node.expanded, false)
  r.assert_eq(ts._expanded.changes, true)
  r.assert_eq(current().node.children[1].expanded, false)
  r.assert_eq(current().node.children[1].children[1].expanded, false)
  r.assert_eq(ts.display_items[1].node.children[2].expanded, true)
  vim.cmd('normal zO')
  r.assert_eq(current().node.children[1].expanded, true)
  r.assert_eq(current().node.children[1].children[1].expanded, true)
  goto_path('a/nested/deep/f')
  vim.cmd('normal zR')
  r.assert_eq(ts._expanded.unstaged, false)
  r.assert_eq(current().node.rel_path, 'a/nested/deep/f')
end)

run('fold keys stay within Changes, Staged and Stashes including lazy loads', function()
  open('git_changes')
  drain()
  local changes = require('lu5je0.ext.sidebar.sources.git_changes')
  local ts = state.git_changes
  changes.update_sections_from_stdout(ts, 'M  staged/f\0 M unstaged/f\0?? untracked/f\0')
  stash_row()
  vim.api.nvim_set_current_win(state.win)
  vim.cmd('normal 3G')
  local function current_path()
    return ts.display_items[vim.api.nvim_win_get_cursor(state.win)[1]].node.rel_path
  end
  local path = current_path()
  r.assert_truthy(path)
  vim.cmd('normal zR')
  r.assert_eq(current_path(), path)
  local function goto_section(name)
    for i, item in ipairs(ts.display_items) do
      if item._is_section and item.section == name then
        vim.api.nvim_win_set_cursor(state.win, { i, 0 })
        return
      end
    end
    error('missing section ' .. name)
  end
  local function check_sections(staged, stashes)
    r.assert_eq(ts._expanded, {
      changes = true, staged = staged, unstaged = false, untracked = false, stashes = stashes,
    })
  end
  check_sections(false, false)
  goto_section('staged')
  vim.cmd('normal zR')
  check_sections(true, false)
  vim.cmd('normal zC')
  check_sections(false, false)
  r.assert_eq(ts.display_items[vim.fn.line('.')].node.children[1].expanded, false)
  vim.cmd('normal zO')
  check_sections(true, false)
  vim.cmd('normal 2j')
  r.assert_eq(current_path(), 'staged/f')
  r.assert_eq(#pending, 0)

  goto_section('stashes')
  vim.cmd('normal zR')
  check_sections(true, true)
  vim.cmd('normal zC')
  check_sections(true, false)
  pending[1].callback { code = 0, stdout = 'stash@{0}\0one\nstash@{1}\0two\n' }
  drain()
  r.assert_eq(#pending, 1)
  for _, entry in ipairs(ts._stash_entries) do r.assert_truthy(not entry.expanded) end

  vim.cmd('normal zo')
  r.assert_eq(#pending, 2)
  pending[2].callback { code = 0, stdout = 'stash@{0}\0one\nstash@{1}\0two\n' }
  drain()
  vim.cmd('normal jzo')
  r.assert_eq(#pending, 3)
  pending[3].callback { code = 0, stdout = 'M\tdir/file\n' }
  drain()
  r.assert_eq(ts._stash_entries[1].expanded, true)
  r.assert_eq(ts._stash_entries[1].children[1].expanded, false)

  goto_section('stashes')
  vim.cmd('normal zO')
  r.assert_eq(#pending, 4)
  pending[4].callback { code = 0, stdout = 'M\tdir/file\n' }
  drain()
  for _, entry in ipairs(ts._stash_entries) do
    r.assert_eq(entry.expanded, true)
    r.assert_eq(entry.children[1].expanded, true)
  end
  vim.cmd('normal jzC')
  check_sections(true, true)
  r.assert_eq(ts._stash_entries[1].expanded, false)
  r.assert_eq(ts._stash_entries[1].children[1].expanded, false)
  r.assert_eq(ts._stash_entries[2].children[1].expanded, true)
end)

for _, kind in ipairs { 'list', 'empty cached list', 'files' } do
  local files = kind == 'files'
  run(('cancelled stash %s can be expanded and loaded after returning'):format(kind), function()
    open('git_changes')
    drain()
    local changes = require('lu5je0.ext.sidebar.sources.git_changes')
    local row = stash_row()
    if kind == 'empty cached list' then
      state.git_changes._stash_entries = {}
    end
    vim.api.nvim_win_set_cursor(state.win, { row, 0 })
    changes.open_node()
    if files then
      pending[#pending].callback { code = 0, stdout = 'stash@{0}\0fixture stash\n' }
      drain()
      vim.api.nvim_win_set_cursor(state.win, { row + 1, 0 })
      changes.open_node()
    end
    local interrupted = pending[#pending]
    open('files')
    open('git_changes')
    r.assert_truthy(interrupted.killed)
    local retry_row = files and row + 1 or row
    local item = state.git_changes.display_items[retry_row]
    r.assert_truthy(not item.node.expanded, 'cancelled loading must leave a retryable collapsed node')
    vim.api.nvim_win_set_cursor(state.win, { retry_row, 0 })
    local count = #pending
    changes.open_node()
    r.assert_eq(#pending, count + 1)
    local output = files and 'M\tdemo.txt\n' or 'stash@{0}\0fixture stash\n'
    interrupted.callback { code = 0, stdout = output }
    pending[#pending].callback { code = 0, stdout = output }
    drain()
    local lines = table.concat(text(), '\n')
    r.assert_truthy(lines:find(files and 'demo.txt' or 'fixture stash', 1, true))
  end)
end

run('leaving Files disposes a pending filter overlay without reopening it', function()
  open('files')
  require('lu5je0.ext.sidebar.sources.files.live_filter').start()
  local buf = state.files._live_filter.buf
  open('buffers')
  drain()
  r.assert_eq(state.files._live_filter.buf, nil)
  r.assert_truthy(not vim.api.nvim_buf_is_valid(buf))
end)

run('History preview reopening ignores old BufLeave and switching releases the float', function()
  state.history.loaded = true
  state.history.commits = { { hash = 'abcdef1', short_hash = 'abcdef1', author = 'Test', date = '2026-01-01', message = 'fixture', parents = '', files = {} } }
  open('history')
  drain()
  local preview = require('lu5je0.ext.sidebar.actions.preview')
  preview.toggle()
  vim.api.nvim_exec_autocmds('BufLeave', { buffer = state.buf })
  preview.stop()
  preview.toggle()
  drain()
  local p = state.preview
  r.assert_truthy(p.active and p.text_win and vim.api.nvim_win_is_valid(p.text_win))
  local buf = p.text_buf
  open('files')
  r.assert_eq(p.text_win, nil)
  r.assert_truthy(not vim.api.nvim_buf_is_valid(buf))
  open('history')
  preview.toggle()
  local float = state.preview.text_win
  vim.api.nvim_win_close(state.win, true)
  r.assert_eq(state.preview.text_win, nil)
  r.assert_truthy(not vim.api.nvim_win_is_valid(float))
end)

for _, external in ipairs { false, true } do
  run((external and 'external window close' or 'explicit close') .. ' cancels requests, timers and rejects late results', function(source_win)
    open('symbols', { source_win = source_win })
    local ts, request = state.tab(), requests[#requests]
    local ctx = lifecycle.capture()
    symbols.follow(ctx, 1)
    local timer = ts.symbols.follow_timer
    if external then
      vim.api.nvim_win_close(ts.win, true)
    else
      require('lu5je0.ext.sidebar.window').close()
    end
    request.callback(nil, result('closed'))
    drain()
    r.assert_truthy(request.cancelled)
    r.assert_truthy(timer:is_closing())
    r.assert_eq(ts.symbols.follow_timer, nil)
    r.assert_eq(ts.win, nil)
    r.assert_eq(#ts.symbols.nodes, 0)
    r.assert_truthy(not lifecycle.is_current(ctx))
    open('files')
    r.assert_truthy(state:is_open())
  end)
end

run('tabpage leave cancels its source without touching the next tabpage', function(source_win)
  open('symbols', { source_win = source_win })
  local ts, request = state.tab(), requests[#requests]
  local tab = vim.api.nvim_get_current_tabpage()
  vim.cmd('tabnew')
  vim.cmd.edit(fixture .. '/demo.txt')
  open('files')
  local next_state, before = state.tab(), text()
  request.callback(nil, result('old tab'))
  drain()
  r.assert_truthy(request.cancelled)
  r.assert_eq(#ts.symbols.nodes, 0)
  r.assert_eq(text(), before)
  vim.api.nvim_set_current_tabpage(tab)
  requests[#requests].callback(nil, result('resumed'))
  drain()
  r.assert_eq(ts.symbols.nodes[1].name, 'resumed')
  r.assert_eq(#next_state.symbols.nodes, 0)
  vim.cmd('tabclose!')
  r.assert_truthy(ts.disposed)
end)

r.run('E444 preserves the last Sidebar window, context and watchers', function()
  local child = vim.fn.jobstart({ vim.v.progpath, '--headless', '--embed', '-u', 'NONE', '-i', 'NONE', '-n' }, { rpc = true })
  local ok, err = pcall(
    vim.rpcrequest,
    child,
    'nvim_exec_lua',
    [[
    local root, fixture = ...
    vim.opt.runtimepath:prepend(root .. '/vim')
    vim.cmd.cd(fixture)
    require('lu5je0.ext.sidebar').open_tab(1, { no_toggle = true })
    local state = require('lu5je0.ext.sidebar.state')
    local window = require('lu5je0.ext.sidebar.window')
    vim.api.nvim_set_current_win(state.win)
    vim.cmd('only')
    local ts, win = state.tab(), state.win
    local context, generation = ts.source_context, ts.source_generation
    local watchers = ts.files.fs_watchers
    local ok, err = pcall(window.close)
    assert(not ok and tostring(err):find('E444', 1, true), tostring(err))
    assert(state:is_open() and ts.win == win and vim.api.nvim_win_is_valid(win), 'failed close must preserve window ownership')
    assert(ts.source_context == context and ts.source_generation == generation, 'failed close must preserve source context')
    assert(ts.files.fs_watchers == watchers, 'failed close must preserve watchers')
    require('lu5je0.ext.sidebar').focus()
    assert(#vim.api.nvim_tabpage_list_wins(0) == 1, 'focus must not create a duplicate Sidebar')
    vim.cmd('belowright new')
    window.close()
    assert(not state:is_open() and not vim.api.nvim_win_is_valid(win))
  ]],
    { root, fixture }
  )
  vim.fn.jobstop(child)
  if not ok then
    error(err)
  end
end)

vim.system = original_system
vim.lsp.get_clients, vim.lsp.buf_request = original_clients, original_request
vim.fn.delete(fixture, 'rf')
r.finish()
