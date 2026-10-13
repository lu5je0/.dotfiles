-- Winbar close_others spec: <leader>to 的语义。
--
--   cd vim && nvim --headless -u NONE -l tests/winbar/close_others_spec.lua
--
-- 为什么要有这个 spec：这个键曾经直接复用 close_left/close_right，于是吃的是 winbar 的
-- per-window 显示列表（state.win_bufs）。那份列表只包含某个窗口"见过"的 buffer，所以
--   * vsplit 出来的新窗口里按它 → 列表只有 1 个 buffer → 完全没反应
--   * 光标停在侧栏里按它 → 列表是侧栏自己的 buffer → 完全没反应
-- 三条不变量：① 目标是全局 buffer 列表；② 有未保存修改的不动；③ 正显示在别的窗口里的不动
-- （`:bdelete` 会把那个窗口一起带走）。
local CFG = vim.fn.fnamemodify(vim.fn.getcwd(), ':p'):gsub('/$', '')

local total, failed = 0, 0

local Child = {}
Child.__index = Child

function Child.new()
  local ch = vim.fn.jobstart({
    'nvim', '--embed', '-u', 'NONE',
    '--cmd', 'set rtp+=' .. CFG,
  }, { rpc = true })
  if ch <= 0 then error('failed to spawn child nvim') end
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

function Child:stop()
  pcall(vim.fn.jobstop, self.ch)
  vim.wait(40)
end

local function check(label, got, want)
  total = total + 1
  local ok = got == want
  if not ok then failed = failed + 1 end
  print(string.format('  %-30s %-28s %s', label, got, ok and 'PASS' or ('FAIL want ' .. want)))
end

-- shared child bootstrap：建命名 buffer + 起 winbar + 把 mapleader 设成 ','（-u NONE 下默认是 \）
local BOOT = [[
  vim.o.swapfile = false
  vim.g.mapleader = ','
  require('lu5je0.ext.winbar.init').setup()
  _G.T = {}
  _G.mk = function(name)
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(b, name)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { name })
    vim.bo[b].modified = false   -- set_lines 会把 buffer 置脏，这里要的是干净 buffer
    return b
  end
  -- 当前列出的 buffer 名字（忽略无名 buffer：nvim 启动时的空 buffer、tabnew 的 scratch）
  _G.listed = function()
    local names = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      local path = vim.api.nvim_buf_get_name(b)
      if vim.bo[b].buflisted and path ~= '' then
        names[#names + 1] = vim.fn.fnamemodify(path, ':t:r')
      end
    end
    return table.concat(names, ',')
  end
  _G.wins = function() return #vim.api.nvim_tabpage_list_wins(0) end
  _G.tabs = function() return #vim.api.nvim_list_tabpages() end
  _G.name_of = function(b) return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':t:r') end
  _G.close_others = function() require('lu5je0.ext.winbar.actions').close_others() end
]]

local function boot()
  local c = Child.new()
  c:exec(BOOT)
  return c
end

--------------------------------------------------------------------------------
print('scenario: mapping is registered (winbar setup_keymaps 是延迟的)')
do
  local c = boot()
  c:exec('vim.wait(500)')
  check('maparg(",to","n") 非空', c:eval('return tostring(vim.fn.maparg(",to", "n") ~= "")'), 'true')
  c:stop()
end

--------------------------------------------------------------------------------
print('scenario: single window closes every other buffer')
do
  local c = boot()
  c:exec([[
    T.a, T.b, T.c, T.d = mk('a'), mk('b'), mk('c'), mk('d')
    vim.api.nvim_set_current_buf(T.d)
  ]])
  check('before', c:eval('return listed()'), 'a,b,c,d')
  c:exec('close_others()')
  check('after', c:eval('return listed()'), 'd')
  c:stop()
end

--------------------------------------------------------------------------------
print('scenario: modified buffers are never discarded')
do
  local c = boot()
  c:exec([[
    T.a, T.b, T.c, T.d = mk('a'), mk('b'), mk('c'), mk('d')
    vim.bo[T.a].modified = true
    vim.bo[T.c].modified = true
    vim.api.nvim_set_current_buf(T.d)
    close_others()
  ]])
  check('clean ones closed, dirty kept', c:eval('return listed()'), 'a,c,d')
  c:stop()
end

--------------------------------------------------------------------------------
print('scenario: split window — 全局列表 + 别的窗口可见的不动')
do
  local c = boot()
  c:exec([[
    T.a, T.b, T.c, T.d = mk('a'), mk('b'), mk('c'), mk('d')
    vim.api.nvim_set_current_buf(T.d)
    vim.cmd('vsplit')
    vim.api.nvim_win_set_buf(0, T.b)   -- 新窗口只"见过" b（老实现就是在这里失效的）
  ]])
  check('该窗口的显示列表只有 b', c:eval('return #require("lu5je0.ext.winbar.util").get_buf_list()'), 1)
  c:exec('close_others()')
  check('a/c 关掉，b/可见的 d 留着', c:eval('return listed()'), 'b,d')
  check('两个窗口都还在', c:eval('return tostring(wins())'), '2')
  c:stop()
end

--------------------------------------------------------------------------------
print('scenario: 光标在侧栏里（当前 buffer 是侧栏自己）')
do
  local c = boot()
  c:exec([[
    T.a, T.b, T.c, T.d = mk('a'), mk('b'), mk('c'), mk('d')
    vim.api.nvim_set_current_buf(T.d)
    vim.cmd('topleft vsplit')
    T.sb = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, T.sb)
    vim.bo[T.sb].filetype = 'Sidebar'
    vim.bo[T.sb].buftype = ''
  ]])
  check('当前 buffer 是侧栏', c:eval('return tostring(vim.api.nvim_get_current_buf() == T.sb)'), 'true')
  c:exec('close_others()')
  check('a/b/c 关掉，编辑器窗口显示的 d 留着', c:eval('return listed()'), 'd')
  check('侧栏窗口还在', c:eval('return tostring(wins())'), '2')
  check('侧栏 buffer 没被删', c:eval('return tostring(vim.api.nvim_buf_is_valid(T.sb))'), 'true')
  c:stop()
end

--------------------------------------------------------------------------------
print('scenario: 第二个 tabpage（跨 tabpage 可见的也不动）')
do
  local c = boot()
  c:exec([[
    T.a, T.b, T.c, T.d = mk('a'), mk('b'), mk('c'), mk('d')
    vim.api.nvim_set_current_buf(T.d)   -- tab 1 显示 d
    vim.cmd('tabnew')
    T.scratch = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(T.b)   -- tab 2 显示 b
  ]])
  c:exec('close_others()')
  check('a/c 关掉，b 与 tab1 的 d 留着', c:eval('return listed()'), 'b,d')
  check('tab2 的 scratch 也被关掉', c:eval('return tostring(vim.bo[T.scratch].buflisted)'), 'false')
  check('tabpage 数不变', c:eval('return tostring(tabs())'), '2')
  check('tab1 的窗口没被带走', c:eval([[
    local w = vim.api.nvim_tabpage_list_wins(1)
    return tostring(#w == 1 and name_of(vim.api.nvim_win_get_buf(w[1])))
  ]]), 'd')
  c:stop()
end

print(string.format('\n%d passed, %d failed', total - failed, failed))
os.exit(failed == 0 and 0 or 1)
