-- Real UI regression tests for restoring the Sidebar viewport after closing.
-- Usage: cd vim && nvim --headless -u NONE -i NONE -n -l tests/sidebar/scroll_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
local h = dofile(root .. '/vim/tests/sidebar/helpers.lua').make_runner()
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, 'p')
for i = 1, 120 do
  vim.fn.writefile({}, fixture .. ('/file-%03d.txt'):format(i))
end
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-u', 'NONE', '-i', 'NONE', '-n' }, {
  rpc = true,
  env = {
    NVIM_LOG_FILE = fixture .. '/.nvim.log',
    XDG_STATE_HOME = fixture .. '/.state',
    XDG_CACHE_HOME = fixture .. '/.cache',
  },
})
assert(child > 0, 'failed to start Neovim')
vim.rpcrequest(child, 'nvim_ui_attach', 120, 30, {})

local function eval(code, ...)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, { ... })
end

eval(
  [[
  local root, fixture = ...
  vim.opt.runtimepath:prepend(root .. '/vim')
  vim.o.mouse = 'a'
  vim.o.scrolloff = 5
  vim.cmd.cd(fixture)
  source_win = vim.api.nvim_get_current_win()
  require('lu5je0.ext.loader').ext_load({
    keys = { { mode = { 'n' }, '<leader>e' } },
    config = function()
      sidebar = require('lu5je0.ext.sidebar')
      state = require('lu5je0.ext.sidebar.state')
      sidebar.setup()
    end,
  })
  function current_view()
    vim.cmd('redraw')
    return vim.api.nvim_win_call(state.win, vim.fn.winsaveview)
  end
  function prepare(focused)
    vim.api.nvim_set_current_win(state.win)
    vim.fn.winrestview({ lnum = 50, col = 0, topline = 40 })
    if not focused then vim.api.nvim_set_current_win(source_win) end
    vim.cmd('redraw')
  end
  rendered_toplines = {}
  vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace('sidebar_scroll_test'), {
    on_win = function(_, _, buf, topline)
      if state and buf == state.buf then
        rendered_toplines[#rendered_toplines + 1] = topline + 1
      end
    end,
  })
]],
  root,
  fixture
)

local function drain()
  vim.wait(50, function()
    return false
  end, 5)
end

local function view()
  return eval('return current_view()')
end

local function wheel(direction)
  local pos = eval('return vim.api.nvim_win_get_position(state.win)')
  for _ = 1, 4 do
    vim.rpcrequest(child, 'nvim_input_mouse', 'wheel', direction, '', 0, pos[1] + 10, pos[2] + 10)
    drain()
  end
end

local function assert_reopened(before, reopen)
  eval('rendered_toplines = {}')
  if reopen then
    eval(reopen)
  else
    vim.rpcrequest(child, 'nvim_input', '\\e')
    h.assert_truthy(vim.wait(2000, function()
      return eval('return not state:is_open()')
    end, 10))
    vim.rpcrequest(child, 'nvim_input', '\\e')
    h.assert_truthy(vim.wait(2000, function()
      return eval('return state:is_open()')
    end, 10))
  end
  drain()
  h.assert_eq(view(), before)
  local rendered = eval('return rendered_toplines')
  h.assert_truthy(#rendered > 0, 'must observe actual Sidebar redraws')
  for _, topline in ipairs(rendered) do
    h.assert_eq(topline, before.topline, 'every displayed frame must use the saved view: ' .. vim.inspect(rendered))
  end
end

h.group('Sidebar scroll restoration')
h.run('first lazy toggle opens Files without stealing focus', function()
  h.assert_eq(eval("return package.loaded['lu5je0.ext.sidebar'] ~= nil"), false)
  vim.rpcrequest(child, 'nvim_input', '\\e')
  h.assert_truthy(vim.wait(2000, function()
    return eval('return state ~= nil and state:is_open()')
  end, 10))
  drain()
  h.assert_eq(eval('return vim.api.nvim_get_current_win()'), eval('return source_win'))
end)

for _, focused in ipairs { false, true } do
  for _, direction in ipairs { 'down', 'up' } do
    h.run(('wheel %s in %s Sidebar survives toggle'):format(direction, focused and 'focused' or 'unfocused'), function()
      eval('prepare(...)', focused)
      local before = view()
      wheel(direction)
      local scrolled = view()
      h.assert_truthy(scrolled.topline ~= before.topline, 'mouse wheel must actually scroll')
      assert_reopened(scrolled)
      h.assert_eq(eval('return vim.api.nvim_get_current_win()'), eval('return source_win'))
    end)
  end
end

for _, key in ipairs { '<C-d>', '<C-u>' } do
  h.run(key .. ' paging survives toggle', function()
    eval('prepare(true)')
    local before = view()
    vim.rpcrequest(child, 'nvim_input', key)
    drain()
    local scrolled = view()
    h.assert_truthy(scrolled.topline ~= before.topline, 'paging must actually scroll')
    assert_reopened(scrolled)
  end)
end

for _, reopen in ipairs { 'sidebar.focus()', 'sidebar.open_tab(1, { focus = false })' } do
  h.run(reopen .. ' restores the closed view', function()
    eval('prepare(false)')
    wheel('down')
    assert_reopened(view(), 'sidebar.toggle(); ' .. reopen)
  end)
end

h.run('focus on an open Sidebar preserves the current view', function()
  eval('prepare(true)')
  wheel('up')
  local before = view()
  eval('sidebar.focus()')
  drain()
  h.assert_eq(view(), before)
end)

h.run('external window close saves the latest view', function()
  eval('prepare(false)')
  wheel('down')
  assert_reopened(view(), 'vim.api.nvim_win_close(state.win, true); sidebar.toggle({ focus = false })')
end)

for _, action in ipairs { 'copy', 'cut' } do
  h.run(action .. ' marks survive reopening without intermediate frames', function()
    eval(
      [[
      prepare(true)
      require('lu5je0.ext.sidebar.actions.file_ops')[...]()
    ]],
      action
    )
    wheel('down')
    assert_reopened(view())
    local marks = eval([[
      return vim.api.nvim_buf_get_extmarks(state.buf,
        vim.api.nvim_create_namespace('sidebar_clipboard'), 0, -1, { details = true })
    ]])
    h.assert_eq(#marks, 1)
    h.assert_eq(marks[1][4].line_hl_group, action == 'copy' and 'SidebarCopy' or 'SidebarCut')
  end)
end

vim.fn.jobstop(child)
vim.fn.delete(fixture, 'rf')
h.finish()
