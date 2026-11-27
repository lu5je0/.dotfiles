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

h.group('Sidebar Files filter')
local function input(keys)
  vim.rpcrequest(child, 'nvim_input', keys)
end

local function wait_for(code)
  h.assert_truthy(vim.wait(4000, function() return eval(code) end, 5), code)
end

h.run('Files filter edits the top row and applies only on Enter', function()
  eval([[
    vim.api.nvim_set_current_win(state.win)
    state.files._clipboard = nil
    vim.o.laststatus = 3
    require('lu5je0.ext.statusline').setup()
    vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 0x314159 })
    vim.api.nvim_set_hl(0, 'CursorLine', { bg = 0x493011 })
    filter_frames = {}
    unfiltered_items = state.files.display_items
    unfiltered_count = #unfiltered_items
    root_item = unfiltered_items[1]
    vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace('sidebar_filter_test'), {
      on_win = function(_, _, buf)
        if buf == state.buf then
          local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
          if line and vim.startswith(line, '[FILTER]: ') then
            filter_frames[#filter_frames + 1] = line
          end
        end
      end,
    })
    function statusline_text()
      vim.cmd.redrawstatus()
      local cells = {}
      for col = 1, vim.o.columns do
        cells[col] = vim.fn.screenstring(vim.o.lines - vim.o.cmdheight, col)
      end
      return table.concat(cells)
    end
    function filter_row_backgrounds(editing)
      vim.cmd.redraw()
      local pos = vim.fn.screenpos(state.win, 1, 1)
      local right = vim.fn.win_screenpos(state.win)[2] + vim.api.nvim_win_get_width(state.win) - 1
      local function background(col)
        return vim.api.nvim__inspect_cell(1, pos.row - 1, col - 1)[2].background
      end
      -- While editing, the float covers the right side of the main grid.
      if editing then return { background(pos.col) } end
      return { background(pos.col), background(right) }
    end
  ]])
  local before = eval('return statusline_text()')
  h.assert_truthy(before:find('SIDEBAR', 1, true))
  local function open_filter()
    input('f')
    wait_for("return vim.fn.mode() == 'i' and state.files.filter_prompt and vim.api.nvim_get_current_win() == state.files.filter_prompt.win")
  end
  open_filter()
  eval([[
    local popup = vim.api.nvim_win_get_config(state.files.filter_prompt.win)
    assert(popup.relative == 'win' and popup.win == state.win and popup.bufpos[1] == 0)
    assert(state.files.display_items == unfiltered_items and state.files.display_items[2] == root_item)
    assert(root_item.line_idx == 1 and #unfiltered_items == unfiltered_count + 1)
  ]])
  h.assert_eq(eval('return statusline_text()'), before)
  local frames = eval('return filter_frames')
  h.assert_truthy(#frames > 0, 'must observe actual Sidebar redraws')
  for _, line in ipairs(frames) do
    h.assert_eq(line, '[FILTER]: ')
  end
  local tick = eval('return vim.api.nvim_buf_get_changedtick(state.buf)')
  input('file-001')
  wait_for("return vim.api.nvim_get_current_line() == 'file-001'")
  h.assert_eq(eval('return vim.api.nvim_buf_get_changedtick(state.buf)'), tick)
  h.assert_eq(eval('return state.files.live_filter'), vim.NIL)
  local prompt_text = eval([[
    vim.cmd.redraw()
    local pos = vim.fn.screenpos(state.win, 1, 1)
    local cells = {}
    for col = pos.col, pos.col + #'[FILTER]: file-001' - 1 do
      cells[#cells + 1] = vim.fn.screenstring(pos.row, col)
    end
    return table.concat(cells)
  ]])
  h.assert_eq(prompt_text, '[FILTER]: file-001')
  h.assert_eq(eval('return filter_row_backgrounds(true)'), { 0x314159 })
  h.assert_eq(eval('return statusline_text()'), before)
  input('<CR>')
  wait_for("return state.files.live_filter == 'file-001' and vim.api.nvim_get_current_win() == state.win")
  h.assert_eq(eval('return statusline_text()'), before)
  local function header()
    return eval('return vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1]')
  end
  h.assert_eq(header(), '[FILTER]: /file-001/')
  h.assert_eq(eval('return #state.files.display_items'), 3)
  h.assert_eq(eval('return filter_row_backgrounds()'), { 0x314159, 0x314159 })
  input('j')
  wait_for('return vim.api.nvim_win_get_cursor(state.win)[1] == 2')
  h.assert_eq(eval('return filter_row_backgrounds()'), { 0x314159, 0x314159 })

  open_filter()
  h.assert_eq(eval('return vim.api.nvim_get_current_line()'), 'file-001')
  input('<C-u>file-002<Esc>')
  wait_for('return not state.files.filter_prompt and vim.api.nvim_get_current_win() == state.win')
  h.assert_eq(header(), '[FILTER]: /file-001/')
  h.assert_eq(eval('return state.files.live_filter'), 'file-001')

  open_filter()
  input('<C-u><CR>')
  wait_for('return not state.files.filter_prompt and not state.files.live_filter and vim.api.nvim_get_current_win() == state.win')
  h.assert_eq(eval('return #state.files.display_items'), eval('return unfiltered_count'))

  open_filter()
  input('file-001<CR>')
  wait_for("return state.files.live_filter == 'file-001' and not state.files.filter_prompt")
  input('F')
  wait_for("return not state.files.live_filter and state.files.display_items[1].type == 'root'")
end)

h.group('Sidebar Files folds')

h.run('zo and zc fold one level, and zO expands just the current subtree', function()
  eval([[
    local fixture = ... .. '/.folds'
    for _, path in ipairs({ 'branch/nested/deep', 'other/side', '.hidden/nested' }) do
      vim.fn.mkdir(fixture .. '/' .. path, 'p')
      vim.fn.writefile({}, fixture .. '/' .. path .. '/leaf.txt')
    end
    assert(vim.uv.fs_symlink(fixture, fixture .. '/loop', { dir = true }))
    vim.cmd.cd(fixture)
    function row_for(path)
      for row, item in ipairs(state.files.display_items) do
        if item.node and item.node.abs_path == fixture .. '/' .. path then return row end
      end
    end
    function goto_path(path)
      vim.api.nvim_win_set_cursor(state.win, { assert(row_for(path), path), 0 })
    end
    goto_path('branch')
  ]], fixture)
  input('zo')
  wait_for("return row_for('branch/nested') ~= nil")
  h.assert_eq(eval("return row_for('branch/nested/deep')"), vim.NIL)
  input('zoj')
  wait_for("return vim.api.nvim_get_current_win() == state.win and vim.fn.line('.') == row_for('branch/nested')")
  input('zc')
  wait_for("return row_for('branch/nested') == nil")
  input('zozO')
  wait_for("return row_for('branch/nested/deep/leaf.txt') ~= nil")
  h.assert_eq(eval("return row_for('other/side')"), vim.NIL)
  h.assert_eq(eval("return vim.fn.line('.') == row_for('branch')"), true)
  eval("goto_path('branch/nested/deep/leaf.txt')")
  input('zo')
  drain()
  h.assert_eq(eval("return vim.api.nvim_get_current_win() == state.win and vim.fn.line('.') == row_for('branch/nested/deep/leaf.txt')"), true)
  eval("goto_path('other')")
  input('zc')
  drain()
  h.assert_truthy(eval("return row_for('branch/nested/deep/leaf.txt') ~= nil"))
end)

h.run('zC closes the Files directory and its descendants and leaves siblings open', function()
  eval("goto_path('other')")
  input('zO')
  wait_for("return row_for('other/side/leaf.txt') ~= nil")
  eval("goto_path('branch/nested/deep/leaf.txt')")
  input('zC')
  wait_for("return vim.fn.line('.') == row_for('branch/nested/deep') and row_for('branch/nested/deep/leaf.txt') == nil")
  h.assert_truthy(eval("return row_for('other/side/leaf.txt') ~= nil"))
  eval("goto_path('branch')")
  input('zC')
  wait_for("return row_for('branch/nested') == nil and vim.fn.line('.') == row_for('branch')")
  h.assert_truthy(eval("return row_for('other/side/leaf.txt') ~= nil"))
  input('zo')
  wait_for("return row_for('branch/nested') ~= nil")
  h.assert_eq(eval("return row_for('branch/nested/deep')"), vim.NIL)
  eval("goto_path('branch/nested')")
  input('zo')
  wait_for("return row_for('branch/nested/deep') ~= nil")
  h.assert_eq(eval("return row_for('branch/nested/deep/leaf.txt')"), vim.NIL)
end)

h.run('zR renders partial results, Esc stops scanning, and zR finishes on retry', function()
  eval([[
    for i = 1, 512 do
      local dir = ('many/dir-%03d/deep'):format(i)
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({}, dir .. '/leaf.txt')
    end
    require('lu5je0.ext.sidebar.sources.files').refresh()
    vim.api.nvim_win_set_cursor(state.win, { row_for('other'), 4 })
    fold_frame_rows = 0
    vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace('sidebar_expand_test'), {
      on_win = function(_, _, buf)
        if buf == state.buf and state.files.expand_job then
          fold_frame_rows = math.max(fold_frame_rows, #state.files.display_items)
        end
      end,
    })
  ]])
  local before = eval('return #state.files.display_items')
  input('zR')
  wait_for(('return fold_frame_rows > %d and state.files.expand_job ~= nil'):format(before))
  input('<Esc>')
  wait_for('return state.files.expand_job == nil')
  local stopped = eval('return #state.files.display_items')
  h.assert_truthy(stopped > before)
  h.assert_eq(eval("return row_for('many/dir-512/deep/leaf.txt')"), vim.NIL)
  drain()
  h.assert_eq(eval('return #state.files.display_items'), stopped)
  input('zR')
  wait_for("return row_for('many/dir-512/deep/leaf.txt') ~= nil and state.files.expand_job == nil")
  h.assert_eq(eval("return vim.api.nvim_win_get_cursor(state.win)"), { eval("return row_for('other')"), 4 })
  h.assert_eq(eval("return row_for('loop/branch') or row_for('.hidden')"), vim.NIL)
end)

h.run('closing a fold or leaving Files cancels pending expansion', function()
  eval("goto_path('many')")
  input('zc')
  wait_for("return row_for('many/dir-001') == nil")
  input('zO')
  wait_for("return state.files.expand_job ~= nil and row_for('many/dir-001/deep') ~= nil")
  h.assert_eq(eval("return row_for('many/dir-512/deep/leaf.txt')"), vim.NIL)
  input('zC')
  wait_for("return state.files.expand_job == nil and row_for('many/dir-001') == nil")
  input('zO')
  wait_for("return state.files.expand_job ~= nil and row_for('many/dir-001/deep') ~= nil")
  h.assert_eq(eval("return row_for('many/dir-512/deep/leaf.txt')"), vim.NIL)
  input('<Right>')
  wait_for('return state.active_tab_idx == 2 and state.files.expand_job == nil')
  input('<Left>')
  wait_for('return state.active_tab_idx == 1')
  h.assert_eq(eval("return row_for('many/dir-512/deep/leaf.txt')"), vim.NIL)
end)

vim.fn.jobstop(child)
vim.fn.delete(fixture, 'rf')
h.finish()
