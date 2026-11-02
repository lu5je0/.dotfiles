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
