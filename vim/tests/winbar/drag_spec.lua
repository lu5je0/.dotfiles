-- Winbar drag spec: drives a child Neovim with a real attached UI so that mouse
-- press/drag/release go through the actual winbar click regions and mappings.
--
--   cd vim && nvim --headless -u NONE -l tests/winbar/drag_spec.lua
--
-- Harness notes:
--  * nvim_ui_attach must be called WITHOUT ext_linegrid; this parent is not a
--    real grid UI and the child exits if it has to emit linegrid events.
--  * mouse input is only meaningful once a UI is attached (a headless child with
--    no UI silently drops nvim_input_mouse).
--  * a tab's separator and centering padding are outside its click region, so
--    press coordinates are derived from state.tab_regions, not guessed.
local CFG = vim.fn.fnamemodify(vim.fn.getcwd(), ':p'):gsub('/$', '')

local total, failed = 0, 0

local Child = {}
Child.__index = Child

function Child.new()
  local ch = vim.fn.jobstart({
    'nvim', '--embed', '-u', 'NONE',
    '--cmd', 'set rtp+=' .. CFG,
    '--cmd', 'set mouse=a',
  }, { rpc = true })
  if ch <= 0 then error('failed to spawn child nvim') end
  vim.rpcrequest(ch, 'nvim_ui_attach', 120, 40, {})
  return setmetatable({ ch = ch }, Child)
end

function Child:eval(code)
  local ok, res = pcall(vim.rpcrequest, self.ch, 'nvim_exec_lua', code, {})
  if not ok then
    print('  CHILD ERROR: ' .. vim.inspect(res))
    self:stop()
    os.exit(1)
  end
  return res
end

function Child:exec(code)
  return self:eval(('local ok, err = pcall(function()\n%s\nend)\nif not ok then error(tostring(err), 0) end')
    :format(code))
end

function Child:mouse(action, row, col)
  vim.rpcrequest(self.ch, 'nvim_input_mouse', 'left', action, '', 0, row, col)
  vim.rpcrequest(self.ch, 'nvim_eval', '1')
  vim.wait(80)
end

function Child:stop()
  pcall(vim.fn.jobstop, self.ch)
  vim.wait(40)
end

-- window row + the screen column at the middle of a given tab's click region
function Child:tab_pos(win_key, ordinal)
  return self:eval(([[
    local state = require('lu5je0.ext.winbar.state')
    local w = T.%s
    local col
    for _, r in ipairs(state.tab_regions[w] or {}) do
      if r.ordinal == %d then col = math.floor((r.from + r.to) / 2) end
    end
    local p = vim.api.nvim_win_get_position(w)
    return { row = p[1], col = p[2] + (col or 5) - 1, found = col ~= nil }
  ]]):format(win_key, ordinal))
end

function Child:layout(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = ("L(T.%s)"):format(k)
  end
  return self:eval(([[
    local state = require('lu5je0.ext.winbar.state')
    local function L(w)
      if not w or not vim.api.nvim_win_is_valid(w) then return 'CLOSED' end
      local names = {}
      for _, b in ipairs(state.win_bufs[w] or {}) do
        local n = vim.api.nvim_buf_get_name(b)
        names[#names + 1] = n == '' and '?' or vim.fn.fnamemodify(n, ':t:r'):upper()
      end
      return '[' .. table.concat(names, ',') .. ']'
    end
    return table.concat({ %s }, ' ')
  ]]):format(table.concat(parts, ', ')))
end

local function check(label, got, want)
  total = total + 1
  local ok = got == want
  if not ok then failed = failed + 1 end
  print(string.format('  %-26s %-20s %s', label, got, ok and 'PASS' or ('FAIL want ' .. want)))
end

-- shared child bootstrap: creates named buffers, sets up winbar, splits
local BOOT = [[
  vim.o.swapfile = false
  require('lu5je0.ext.winbar.init').setup()
  _G.state = require('lu5je0.ext.winbar.state')
  _G.mk = function(name, text)
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(b, name)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { text })
    return b
  end
  _G.T = {}
]]

--------------------------------------------------------------------------------
print('scenario: same buffer in both windows, drag out and back (no release)')
do
  local c = Child.new()
  c:exec(BOOT .. [[
    T.a, T.b = mk('/tmp/a.lua', 'aaa'), mk('/tmp/b.lua', 'bbb')
    vim.cmd('vsplit')
    local w = vim.api.nvim_tabpage_list_wins(0)
    T.wL, T.wR = w[1], w[2]
    state.win_bufs[T.wL] = { T.a, T.b }
    state.win_bufs[T.wR] = { T.a }
    vim.api.nvim_win_set_buf(T.wL, T.a)
    vim.api.nvim_win_set_buf(T.wR, T.a)
    vim.cmd('redraw')
  ]])
  vim.wait(120)
  local keys = { 'wL', 'wR' }
  local L, R = c:tab_pos('wL', 1), c:tab_pos('wR', 1)

  check('initial', c:layout(keys), '[A,B] [A]')
  c:mouse('press', R.row, R.col)
  c:mouse('drag', L.row, L.col)
  check('dragged into left', c:layout(keys), '[A,B] []')
  c:mouse('drag', R.row, R.col)
  check('dragged back to right', c:layout(keys), '[A,B] [A]')
  c:mouse('release', R.row, R.col)
  check('after release', c:layout(keys), '[A,B] [A]')
  check('both windows alive', c:eval('return tostring(#vim.api.nvim_tabpage_list_wins(0))'), '2')
  c:stop()
end

--------------------------------------------------------------------------------
print('scenario: move a tab to the other window (source keeps its other tabs)')
do
  local c = Child.new()
  c:exec(BOOT .. [[
    T.a, T.b, T.c = mk('/tmp/a.lua', 'aaa'), mk('/tmp/b.lua', 'bbb'), mk('/tmp/c.lua', 'ccc')
    vim.cmd('vsplit')
    local w = vim.api.nvim_tabpage_list_wins(0)
    T.wL, T.wR = w[1], w[2]
    state.win_bufs[T.wL] = { T.a, T.b }
    state.win_bufs[T.wR] = { T.c }
    vim.api.nvim_win_set_buf(T.wL, T.a)
    vim.api.nvim_win_set_buf(T.wR, T.c)
    vim.cmd('redraw')
  ]])
  vim.wait(120)
  local keys = { 'wL', 'wR' }
  local L2, R = c:tab_pos('wL', 2), c:tab_pos('wR', 1)

  check('initial', c:layout(keys), '[A,B] [C]')
  c:mouse('press', L2.row, L2.col)      -- grab B
  c:mouse('drag', R.row, R.col)
  c:mouse('release', R.row, R.col)
  check('B moved to right', c:layout(keys), '[A] [B,C]')
  check('both windows alive', c:eval('return tostring(#vim.api.nvim_tabpage_list_wins(0))'), '2')
  c:stop()
end

--------------------------------------------------------------------------------
print('scenario: dragging out the last tab closes the split on release only')
do
  local c = Child.new()
  c:exec(BOOT .. [[
    T.a, T.b = mk('/tmp/a.lua', 'aaa'), mk('/tmp/b.lua', 'bbb')
    vim.cmd('vsplit')
    local w = vim.api.nvim_tabpage_list_wins(0)
    T.wL, T.wR = w[1], w[2]
    state.win_bufs[T.wL] = { T.a }
    state.win_bufs[T.wR] = { T.b }
    vim.api.nvim_win_set_buf(T.wL, T.a)
    vim.api.nvim_win_set_buf(T.wR, T.b)
    vim.cmd('redraw')
  ]])
  vim.wait(120)
  local keys = { 'wL', 'wR' }
  local L, R = c:tab_pos('wL', 1), c:tab_pos('wR', 1)

  check('initial', c:layout(keys), '[A] [B]')
  c:mouse('press', L.row, L.col)
  c:mouse('drag', R.row, R.col)
  check('left emptied, still open', c:layout(keys), '[] [A,B]')
  check('windows before release', c:eval('return tostring(#vim.api.nvim_tabpage_list_wins(0))'), '2')
  check('left winbar is empty', c:eval([[
    local r = require('lu5je0.ext.winbar.render').winbar(T.wL)
    return (r:gsub('%%#[^#]*#', '') == '') and 'empty' or ('text:' .. r)
  ]]), 'empty')
  c:mouse('release', R.row, R.col)
  check('windows after release', c:eval('return tostring(#vim.api.nvim_tabpage_list_wins(0))'), '1')
  c:stop()
end

--------------------------------------------------------------------------------
print('scenario: reorder within a single window')
do
  local c = Child.new()
  c:exec(BOOT .. [[
    T.a, T.b, T.c = mk('/tmp/a.lua', 'aaa'), mk('/tmp/b.lua', 'bbb'), mk('/tmp/c.lua', 'ccc')
    T.w = vim.api.nvim_get_current_win()
    state.buf_order = { T.a, T.b, T.c }
    state.win_bufs[T.w] = { T.a, T.b, T.c }
    vim.api.nvim_win_set_buf(T.w, T.a)
    vim.cmd('redraw')
  ]])
  vim.wait(120)
  local function order()
    return c:eval([[
      local names = {}
      for _, b in ipairs(require('lu5je0.ext.winbar.state').buf_order) do
        local n = vim.api.nvim_buf_get_name(b)
        if n ~= '' then names[#names + 1] = vim.fn.fnamemodify(n, ':t:r'):upper() end
      end
      return table.concat(names, ',')
    ]])
  end
  local t1, t3 = c:tab_pos('w', 1), c:tab_pos('w', 3)

  check('initial order', order(), 'A,B,C')
  c:mouse('press', t1.row, t1.col)   -- grab A
  c:mouse('drag', t3.row, t3.col)    -- drag its centre over the 3rd slot
  check('A reordered to the end', order(), 'B,C,A')

  -- mid-drag the grabbed tab is floating, so a frame is present and every frame
  -- is well-formed (fits the window, balanced click regions).
  check('slide frame while dragging', c:eval([[
    return tostring(require('lu5je0.ext.winbar.anim').frame(T.w) ~= nil)
  ]]), 'true')
  check('frames well-formed', c:eval([[
    local anim = require('lu5je0.ext.winbar.anim')
    local ncols = vim.api.nvim_win_get_width(T.w)
    local ok = true
    for _ = 1, 40 do
      local f = anim.frame(T.w)
      if not f then break end
      local plain = f:gsub('%%#[^#]*#', ''):gsub('%%%d*@[^@]*@', ''):gsub('%%X', '')
      if vim.api.nvim_strwidth(plain) > ncols then ok = false end
      if select(2, f:gsub('%%%d*@[^@]*@', '')) ~= select(2, f:gsub('%%X', '')) then ok = false end
      anim.tick()
    end
    return tostring(ok)
  ]]), 'true')

  -- on release the grabbed tab eases into its slot and the animation settles.
  c:mouse('release', t3.row, t3.col)
  check('animation settles after release', c:eval([[
    local anim = require('lu5je0.ext.winbar.anim')
    for _ = 1, 60 do
      if anim.frame(T.w) == nil then break end
      anim.tick()
    end
    return tostring(anim.frame(T.w) == nil)
  ]]), 'true')
  check('final order', order(), 'B,C,A')
  c:stop()
end

--------------------------------------------------------------------------------
print('scenario: after a cross-window move, reordering in the new host animates')
do
  local c = Child.new()
  c:exec(BOOT .. [[
    T.a, T.b = mk('/tmp/a.lua', 'aaa'), mk('/tmp/b.lua', 'bbb')
    T.c, T.d = mk('/tmp/c.lua', 'ccc'), mk('/tmp/d.lua', 'ddd')
    vim.cmd('split')            -- stacked, so each strip keeps full width
    local w = vim.api.nvim_tabpage_list_wins(0)
    T.wL, T.wR = w[1], w[2]
    state.win_bufs[T.wL] = { T.a, T.b }
    state.win_bufs[T.wR] = { T.c, T.d }
    vim.api.nvim_win_set_buf(T.wL, T.a)
    vim.api.nvim_win_set_buf(T.wR, T.c)
    vim.cmd('redraw')
  ]])
  vim.wait(120)
  local keys = { 'wL', 'wR' }
  local L1 = c:tab_pos('wL', 1)
  local R1, R2 = c:tab_pos('wR', 1), c:tab_pos('wR', 2)

  check('initial', c:layout(keys), '[A,B] [C,D]')

  c:mouse('press', L1.row, L1.col)
  c:mouse('drag', R1.row, R1.col)          -- carry A into the other window
  check('A moved across', c:layout(keys), '[B] [A,C,D]')
  check('new host animating', c:eval([[
    return tostring(require('lu5je0.ext.winbar.anim').frame(T.wR) ~= nil)
  ]]), 'true')
  check('old host gap easing', c:eval([[
    return tostring(require('lu5je0.ext.winbar.anim').frame(T.wL) ~= nil)
  ]]), 'true')

  -- keep dragging inside the new host: this used to lose the animation because
  -- the follow path only ran for the drag's origin window.
  c:mouse('drag', R2.row, R2.col)
  check('reordered in new host', c:layout(keys), '[B] [C,A,D]')
  check('still animating there', c:eval([[
    return tostring(require('lu5je0.ext.winbar.anim').frame(T.wR) ~= nil)
  ]]), 'true')

  c:mouse('release', R2.row, R2.col)
  check('settles after release', c:eval([[
    local anim = require('lu5je0.ext.winbar.anim')
    for _ = 1, 80 do
      if anim.frame(T.wR) == nil and anim.frame(T.wL) == nil then break end
      anim.tick()
    end
    return tostring(anim.frame(T.wR) == nil and anim.frame(T.wL) == nil)
  ]]), 'true')
  check('final layout', c:layout(keys), '[B] [C,A,D]')
  c:stop()
end

print(string.format('\n%d passed, %d failed', total - failed, failed))
os.exit(failed == 0 and 0 or 1)
