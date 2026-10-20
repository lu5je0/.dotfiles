-- Real-key regressions: edit with native multicursors, then reset through the actual Git/DiffBase mappings.
-- Usage: nvim --headless -u NONE -i NONE -n -l tests/multicursor/git_reset_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.rtp:append(root .. '/vim')
if not require('lu5je0.ext.multicursor').supported then
  print('SKIP: native multicursor is unavailable in this Neovim build')
  os.exit(0)
end

local plugin = vim.fn.stdpath('data') .. '/lazy/gitsigns.nvim'
local children, repos = {}, {}
local passed, failed = 0, 0
local base = { 'foo one', 'foo two', 'foo three', 'tail' }

local function eq(actual, expected)
  assert(vim.deep_equal(actual, expected), 'actual: ' .. vim.inspect(actual) .. '\nexpected: ' .. vim.inspect(expected))
end

local function child(backend, original)
  original = original or base
  local repo = vim.fn.tempname() .. '-mcursor-reset'
  repos[#repos + 1] = repo
  vim.fn.mkdir(repo, 'p')
  if backend == 'gitsigns' then
    local function git(args)
      local cmd = { 'git', '-C', repo }
      vim.list_extend(cmd, args)
      local result = vim.system(cmd, { text = true }):wait()
      assert(result.code == 0, result.stderr)
    end
    git { 'init', '-q' }
    vim.fn.writefile(original, repo .. '/demo.txt')
    git { 'add', 'demo.txt' }
    git { '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'base' }
  end
  local chan = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n' }, { rpc = true })
  assert(chan > 0)
  children[#children + 1] = chan
  local c = {}
  function c.lua(code, args)
    return vim.rpcrequest(chan, 'nvim_exec_lua', code, args or {})
  end
  function c.feed(keys)
    vim.rpcrequest(chan, 'nvim_input', keys)
    vim.wait(100, function() return false end)
  end
  function c.wait(code)
    if not vim.wait(5000, function() return c.lua(code) end, 25) then
      error('timed out: ' .. code .. '\n' .. vim.inspect({ points = c.points(), lines = c.lines(),
        messages = c.lua([[return vim.api.nvim_exec2('messages', { output = true }).output]]) }))
    end
  end
  function c.points()
    return c.lua([[
      local points = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('nvim.multicursor'), 0, -1, {})) do
        points[#points + 1] = { mark[2] + 1, mark[3] }
      end
      return { primary = vim.api.nvim_win_get_cursor(0), anchors = points, follow = vim.bo.follow }
    ]])
  end
  function c.lines()
    return c.lua([[return vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  end
  function c.updated()
    if backend == 'gitsigns' then
      c.wait([[local h = require('gitsigns').get_hunks(); return h ~= nil and #h > 0]])
    else
      c.wait([[local s = require('lu5je0.ext.diff-base.core').state[vim.api.nvim_get_current_buf()]; return #s.hunks > 0 and s.hunks[1].old_count > 0]])
    end
  end
  c.lua([[
    local root, plugin, repo, backend, original = ...
    vim.opt.rtp:append(root .. '/vim')
    vim.g.mapleader = ','
    require('lu5je0.ext.multicursor').setup()
    if backend == 'gitsigns' then
      vim.opt.rtp:append(plugin)
      require('lu5je0.ext.gitsigns').setup()
      vim.cmd.edit(repo .. '/demo.txt')
    else
      vim.api.nvim_buf_set_lines(0, 0, -1, false, original)
      require('lu5je0.ext.diff-base.core').activate(vim.api.nvim_get_current_buf(), original)
    end
  ]], { root, plugin, repo, backend, original })
  if backend == 'gitsigns' then
    c.wait([[return vim.b.gitsigns_head ~= nil]])
  end
  return c
end

local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS ' .. name)
  else
    failed = failed + 1
    print('FAIL ' .. name .. '\n' .. tostring(err))
  end
  for _, chan in ipairs(children) do pcall(vim.fn.jobstop, chan) end
  for _, repo in ipairs(repos) do vim.fn.delete(repo, 'rf') end
  children, repos = {}, {}
end

for _, backend in ipairs { 'gitsigns', 'diff-base' } do
  if backend == 'gitsigns' and vim.fn.isdirectory(plugin) == 0 then
    print('SKIP: gitsigns.nvim is not installed at ' .. plugin)
  else
    run(backend .. ': reset hunk preserves all three cursors and subsequent editing', function()
      local c = child(backend)
      c.feed('<C-n>')
      c.feed('<C-n>')
      c.feed('ciwBAR<Esc>')
      c.updated()
      local points = c.points()
      eq(points, { primary = { 3, 2 }, anchors = { { 1, 2 }, { 2, 2 } }, follow = true })
      c.feed(',gu')
      eq(c.lines(), base)
      eq(c.points(), points)
      c.feed('rZ')
      eq(c.lines(), { 'foZ one', 'foZ two', 'foZ three', 'tail' })
    end)

    run(backend .. ': reset operates only on the primary hunk', function()
      local original = { 'foo one', 'gap 1', 'gap 2', 'gap 3', 'foo two', 'gap 4', 'gap 5', 'gap 6', 'foo three', 'tail' }
      local c = child(backend, original)
      c.feed('<C-n>')
      c.feed('<C-n>')
      c.feed('ciwBAR<Esc>')
      c.updated()
      local points = c.points()
      c.feed(',gu')
      local expected = vim.deepcopy(original)
      expected[1], expected[5] = 'BAR one', 'BAR two'
      eq(c.lines(), expected)
      eq(c.points(), points)
    end)

    run(backend .. ': reset buffer preserves the cursor set', function()
      local c = child(backend)
      c.feed('<C-n>')
      c.feed('<C-n>')
      c.feed('ciwBAR<Esc>')
      c.updated()
      local points = c.points()
      c.feed(',gC')
      eq(c.lines(), base)
      eq(c.points(), points)
    end)

    run(backend .. ': undo and redo after reset preserve the cursor set', function()
      local c = child(backend)
      c.feed('<C-n>')
      c.feed('<C-n>')
      c.feed('ciwBAR<Esc>')
      c.updated()
      local points = c.points()
      c.feed(',gu')
      eq(c.lines(), base)
      c.feed('u')
      eq(c.lines(), { 'BAR one', 'BAR two', 'BAR three', 'tail' })
      eq(c.points(), points)
      c.feed('<C-r>')
      eq(c.lines(), base)
      eq(c.points(), points)
    end)

    run(backend .. ': Q cursors keep follow disabled after reset', function()
      local c = child(backend)
      c.feed('QjQjciwBAR<Esc>')
      c.updated()
      local points = c.points()
      eq(points.follow, false)
      c.feed(',gu')
      eq(c.lines(), base)
      eq(c.points(), points)
    end)

    run(backend .. ': reset without multicursors keeps its normal behavior', function()
      local c = child(backend)
      c.feed('ciwBAR<Esc>')
      c.updated()
      c.feed(',gu')
      eq(c.lines(), base)
      eq(c.points().anchors, {})
    end)
  end
end

run('bulk reset clamps columns to valid UTF-8 positions', function()
  local original = { '甲', '乙', '丙', 'tail' }
  local c = child('diff-base', original)
  c.feed('<M-n>')
  c.feed('<M-n>')
  c.feed('iABCD<Esc>')
  c.feed(',gC')
  eq(c.lines(), original)
  eq(c.points(), { primary = { 3, 0 }, anchors = { { 1, 0 }, { 2, 0 } }, follow = true })
end)

run('bulk line deletion shifts later cursors without collapsing them', function()
  local c = child('diff-base', { 'foo one', 'remove me', 'foo two', 'foo three', 'tail' })
  c.feed('<C-n>')
  c.feed('<C-n>')
  c.feed('ciwBAR<Esc>')
  c.lua([[
    require('lu5je0.core.multicursor-guard').preserve(function(done)
      vim.api.nvim_buf_set_lines(0, 1, 2, false, {})
      done()
    end)
  ]])
  c.wait([[return vim.api.nvim_buf_line_count(0) == 4 and vim.bo.follow]])
  eq(c.points(), { primary = { 3, 2 }, anchors = { { 1, 2 }, { 2, 2 } }, follow = true })
end)

run('clearing the session during an async reset does not resurrect cursors', function()
  local c = child('diff-base')
  c.feed('<C-n>')
  c.feed('<C-n>')
  c.feed('ciwBAR<Esc>')
  c.lua([[
    require('lu5je0.core.multicursor-guard').preserve(function(done)
      _G.reset_started = true
      vim.defer_fn(function()
        vim.api.nvim_buf_set_lines(0, 0, 3, false, { 'foo one', 'foo two', 'foo three' })
        done()
      end, 250)
    end)
  ]])
  -- 必须等操作已开始，否则 Ctrl-L 可能先取消尚未执行的操作，而不是仅取消恢复。
  c.wait([[return _G.reset_started == true]])
  c.feed('<C-l>')
  c.wait([[return vim.api.nvim_get_current_line() == 'foo three' and not require('vim._core.mcursor').active()]])
  eq(c.points().anchors, {})
  c.lua([[vim.api.nvim_win_set_cursor(0, { 1, 0 })]])
  c.feed('<C-n>')
  eq(c.points(), { primary = { 2, 0 }, anchors = { { 1, 0 } }, follow = true })
end)

run('a failed async reset reports the error and leaves the session usable', function()
  local c = child('diff-base')
  c.feed('<C-n>')
  c.feed('<C-n>')
  c.feed('ciwBAR<Esc>')
  c.updated()
  local points = c.points()
  c.lua([[
    vim.notify = function(message) _G.reset_error = message end
    require('lu5je0.core.multicursor-guard').preserve(function(done) done('reset failed') end)
  ]])
  c.wait([[return _G.reset_error == 'reset failed' and vim.bo.follow]])
  eq(c.points(), points)
  c.feed(',gu')
  eq(c.lines(), base)
  eq(c.points(), points)
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
