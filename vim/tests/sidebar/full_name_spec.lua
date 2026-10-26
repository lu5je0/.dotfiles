-- Real UI regression tests for the long-name overlay and horizontal scrolling.
-- Usage: cd vim && nvim --headless -u NONE -i NONE -n -l tests/sidebar/full_name_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
local h = dofile(root .. '/vim/tests/sidebar/helpers.lua').make_runner()
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-u', 'NONE', '-i', 'NONE', '-n' }, { rpc = true })
assert(child > 0, 'failed to start Neovim')
vim.rpcrequest(child, 'nvim_ui_attach', 120, 30, {})

local function eval(code, ...)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, { ... })
end

eval([[
  vim.opt.runtimepath:prepend(...)
  state = require('lu5je0.ext.sidebar.state')
  vim.cmd('topleft vsplit')
  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, 33)
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.wrap = false
  vim.wo.winbar = 'Files'
  vim.o.sidescrolloff = 5
  require('lu5je0.ext.sidebar.full_name').setup()

  function popup()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then return win end
    end
  end

  function prepare(line, foldcolumn, signcolumn)
    vim.wo[state.win].foldcolumn = foldcolumn
    vim.wo[state.win].signcolumn = signcolumn
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { line, line, line })
    vim.fn.winrestview({ lnum = 2, col = 0, leftcol = 0, topline = 1 })
    vim.cmd('redraw')
  end

  function check_alignment()
    vim.api.nvim_exec_autocmds('CursorMoved', {})
    vim.cmd('redraw')
    local win = assert(popup(), 'long-name popup is missing')
    local info = vim.fn.getwininfo(state.win)[1]
    local pos = vim.fn.screenpos(state.win, 2, 1)
    local above, selected = '', ''
    -- Ignore the final cell, which can contain the extends marker.
    for col = info.wincol + info.textoff, info.wincol + info.width - 2 do
      above = above .. vim.fn.screenstring(pos.row - 1, col)
      selected = selected .. vim.fn.screenstring(pos.row, col)
    end
    local marks = vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(win),
      vim.api.nvim_create_namespace('sidebar_fullname'), 0, -1, { details = true })
    return {
      above = above, selected = selected, win = win,
      leftcol = info.leftcol,
      popup_leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol,
      marks = marks,
    }
  end
]], root .. '/vim')

local name = 'k2nmfgin9xn6x0xa3msc5pc9jwkyswnn-nix-store-2.34.9+1'
local line = 'XX ' .. name

h.group('full-name popup alignment')
for _, gutter in ipairs({ { '0', 'no' }, { '1', 'no' }, { '1', 'yes' } }) do
  h.run('aligns with foldcolumn=' .. gutter[1] .. ', signcolumn=' .. gutter[2], function()
    eval('prepare(...)', line, gutter[1], gutter[2])
    local result = eval('return check_alignment()')
    h.assert_eq(result.selected, result.above)
    h.assert_eq(result.popup_leftcol, 0)
  end)
end

h.run('search in a Nix store name preserves horizontal alignment and highlights', function()
  eval([[
    prepare(...)
    local view = require('lu5je0.ext.sidebar.view')
    view.clear_highlights()
    local col = vim.fn.getline(2):find('store', 1, true) - 1
    view.add_highlight(1, 'Search', col, col + 5)
    vim.fn.search('store', 'c')
    vim.cmd('redraw')
  ]], line, '1', 'no')
  local result = eval('return check_alignment()')
  h.assert_truthy(result.leftcol > 0, 'search must scroll the sidebar horizontally')
  h.assert_eq(result.selected, result.above)
  h.assert_eq(result.popup_leftcol, result.leftcol)
  h.assert_eq(result.marks[1][3], line:find('store', 1, true) - 1)
  h.assert_eq(result.marks[1][4].end_col, line:find('store', 1, true) + 4)
end)

h.run('reused popup stays aligned after scrolling back to the start', function()
  local previous = eval('return popup()')
  eval([[
    vim.fn.winrestview({ col = 0, leftcol = 0 })
    vim.cmd('redraw')
  ]])
  local result = eval('return check_alignment()')
  h.assert_eq(result.win, previous)
  h.assert_eq(result.popup_leftcol, 0)
  h.assert_eq(result.selected, result.above)
end)

h.run('handles wide and multibyte characters while scrolled', function()
  eval([[
    prepare(...)
    vim.api.nvim_win_set_cursor(state.win, { 2, 42 })
    vim.cmd('redraw')
  ]], '目录 ' .. string.rep('中文', 15) .. name, '1', 'no')
  local result = eval('return check_alignment()')
  h.assert_truthy(result.leftcol > 0)
  h.assert_eq(result.popup_leftcol, result.leftcol)
  h.assert_eq(result.selected, result.above)
end)

h.run('hides the popup on a short name', function()
  eval([[
    prepare('short', '1', 'no')
    vim.api.nvim_exec_autocmds('CursorMoved', {})
  ]])
  h.assert_eq(eval('return popup()'), vim.NIL)
end)

vim.fn.jobstop(child)
h.finish()
