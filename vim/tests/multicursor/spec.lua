-- multicursor 原生按键适配测试（仅 Neovim 0.13+）。
-- Usage: cd vim && nvim --headless -u NONE -l tests/multicursor/spec.lua
--
-- 只在本 nvim 支持 vim.api.nvim_mcursor 时真正执行，否则 SKIP（退出码 0）。
-- 所以要在 0.13+ 下跑整套测试才能覆盖这里：NVIM_TEST_BIN 不能把 0.12 的外层“升级”成可跑，
-- 因为 0.12 的 rpcrequest 对着 0.13 子进程会挂死（native RPC 不兼容）。
-- NVIM_TEST_BIN 仅在「外层已是 0.13、想指定另一个 0.13 二进制」时有用。
--
-- 为什么用 RPC 子进程而不是直接在当前 nvim 内测：
--   multicursor 的 CmdAtom / follow-mode 只在「真实按键」路径上才被捕获，
--   vim.api.nvim_feedkeys(..., 'x') 在脚本里不会走 typed 路径，行为不可靠。
--   所以这里起一个 --embed 的子 Neovim，用 nvim_input() 发真实按键。

local function nvim_bin()
  if vim.env.NVIM_TEST_BIN and vim.env.NVIM_TEST_BIN ~= '' then
    return vim.env.NVIM_TEST_BIN
  end
  return vim.v.progpath
end

if type(vim.api.nvim_mcursor) ~= 'function' then
  print('SKIP: native multicursor requires Neovim 0.13+ (vim.api.nvim_mcursor missing)')
  os.exit(0)
end

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
local rtp = repo_root .. '/vim'

local chan = vim.fn.jobstart({ nvim_bin(), '--embed', '--headless', '--cmd', 'set rtp+=' .. rtp }, { rpc = true })
if chan <= 0 then
  print('FAIL: could not start embedded nvim')
  os.exit(1)
end

local function req(method, ...)
  return vim.rpcrequest(chan, method, ...)
end

local function lua(code)
  return req('nvim_exec_lua', code, {})
end

--- Sends real (typed) keys, then lets the main loop settle.
local function feed(keys)
  req('nvim_input', keys)
  vim.wait(150, function()
    return false
  end)
end

local function esc()
  feed(vim.api.nvim_replace_termcodes('<Esc>', true, false, true))
end

local function setup()
  lua([[require('lu5je0.ext.multicursor').setup()]])
end

--- Resets mode, buffer contents, cursors, and follow-mode.
--- 注意：必须先把模式归零（上一个用例可能停在 extend/follow 状态）。
local function reset(buf_lines, cursor)
  feed(vim.api.nvim_replace_termcodes('<Esc>', true, false, true))
  lua(([[
      vim.api.nvim_buf_clear_namespace(0, vim.api.nvim_create_namespace('nvim.multicursor'), 0, -1)
      pcall(vim.cmd, 'normal! 2q=')
      vim.api.nvim_buf_set_lines(0, 0, -1, true, %s)
      vim.api.nvim_win_set_cursor(0, %s)
    ]]):format(buf_lines, cursor))
  -- 清 namespace 会异步触发 enable(false) → sync_cl_map。等一拍，让卸载/还原完成，
  -- 否则上一条用例遗留的 buffer-local <C-l> 会污染下一条。
  vim.wait(60, function()
    return false
  end)
end

local function marks()
  return lua([[
    local ns = vim.api.nvim_create_namespace('nvim.multicursor')
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})) do
      out[#out + 1] = (m[2] + 1) .. ':' .. m[3]
    end
    return table.concat(out, ',')
  ]])
end

local function lines()
  return lua([[return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, true), '|')]])
end

local function mode()
  return lua('return vim.fn.mode()')
end

local function cursor()
  return lua('return vim.inspect(vim.api.nvim_win_get_cursor(0))')
end

local passed, failed = 0, 0

local function group(name)
  print('\n' .. name)
end

local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('  ok   ' .. name)
  else
    failed = failed + 1
    print('  FAIL ' .. name .. '\n       ' .. tostring(err))
  end
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(('%s\n       actual:   %s\n       expected: %s'):format(msg or 'mismatch', vim.inspect(actual), vim.inspect(expected)), 2)
  end
end

setup()

-- ============================================================================
group('<C-n>：加下一个匹配 + 各持选区 + follow-mode')
-- ============================================================================

run('<C-n> 逐个追加 cursor，不合并', function()
  reset([[{'foo bar','foo bar','foo bar','foo bar'}]], '{1, 0}')
  feed('<C-n>')
  assert_eq(marks(), '1:0', 'first press keeps original position')
  feed('<C-n>')
  assert_eq(marks(), '1:0,2:0', 'second press is additive')
  feed('<C-n>')
  assert_eq(marks(), '1:0,2:0,3:0', 'third press is additive')
end)

-- 回归：旧实现在第 3 次按压后 cursor 指数增长（1,2,5,9…）。
-- 原因：上一轮开了 follow-mode，下一轮退出 visual 再移光标，
-- 命中上游 atom_lhs_replay_queue()，把 <C-n> 配方在每个 cursor 上重放。
run('<C-n> 连按多次不会指数增长（无重入级联）', function()
  -- 6 个匹配，5 次按压刚好得到 5 个额外 cursor；第 2、4、6 行的匹配在行中（列不是 0）。
  reset([[{'lu5je0.a','x lu5je0.b','lu5je0.c','x lu5je0.d','lu5je0.e','x lu5je0.f'}]], '{1, 0}')
  for i = 1, 5 do
    feed('<C-n>')
    assert_eq(#vim.split(marks(), ',', { plain = true }), i, ('after %d presses: exactly %d cursors'):format(i, i))
  end
  assert_eq(marks(), '1:0,2:2,3:0,4:2,5:0')
  -- 第 5 次按压后 primary 已到第 6 个匹配，但尚未为它留下锚点；rZ 时 primary 也会被编辑。
  feed('rZ')
  assert_eq(lines(), 'ZZZZZZ.a|x ZZZZZZ.b|ZZZZZZ.c|x ZZZZZZ.d|ZZZZZZ.e|x ZZZZZZ.f')
end)

-- 回归（critical）：这是旧版真正会爆炸的场景，也是「光标闪一下」的修复点。
-- <C-n> 结尾停在 visual，但用户可以按 <Esc> 回 normal 而 follow-mode 仍开着；
-- 此时再按 <C-n>，旧版（无 busy 或包在 schedule 里）就会触发级联。
-- 要求：每次按压精确 +1，不得丢 cursor 或指数增长。
run('<C-n> 在 normal 模式且 follow 已开时仍然精确 +1（不闪烁/不级联）', function()
  reset([[{'lm1 f','lm2 f','lm3 f','lm4 f','lm5 f','lm6 f','lm7 f','lm8 f'}]], '{1, 3}')
  local expected = 0
  for i = 1, 8 do
    -- 每第 3 次先回 normal（follow 保持开启）
    if i % 3 == 0 then
      esc()
      assert_eq(mode(), 'n', 'back to normal')
    end
    feed('<C-n>')
    expected = expected + 1
    local count = #vim.split(marks(), ',', { plain = true })
    assert_eq(count, expected, ('press %d: exactly %d cursors'):format(i, expected))
  end
end)

run('<C-n> 后进入 extend 模式（每个 cursor 各选一个词）', function()
  reset([[{'foo bar','foo bar'}]], '{1, 0}')
  feed('<C-n>')
  assert_eq(mode(), 'v', 'should be in visual mode after <C-n>')
end)

run('<C-n> 的选区可以在所有 cursor 上替换', function()
  reset([[{'foo bar','foo bar','foo bar','foo bar'}]], '{1, 0}')
  feed('<C-n>')
  feed('<C-n>')
  feed('<C-n>')
  esc()
  feed('rZ')
  assert_eq(lines(), 'foZ bar|foZ bar|foZ bar|foZ bar')
  feed('u')
  assert_eq(lines(), 'foo bar|foo bar|foo bar|foo bar', 'undo is atomic')
end)

run('c 可以在每个选区上修改', function()
  reset([[{'aaa baz','aaa baz','aaa baz'}]], '{1, 0}')
  feed('<C-n>')
  feed('<C-n>')
  feed('cZZZ')
  esc()
  assert_eq(lines(), 'ZZZ baz|ZZZ baz|ZZZ baz')
end)

run('I 可以在每个选区前插入', function()
  reset([[{'one x','one x'}]], '{1, 0}')
  feed('<C-n>')
  feed('I# ')
  esc()
  assert_eq(lines(), '# one x|# one x')
end)

run('<C-n> 开启 follow-mode：退出选区后 w 会级联', function()
  reset([[{'aa bb','aa bb','aa bb'}]], '{1, 0}')
  feed('<C-n>')
  feed('<C-n>')
  esc()
  assert_eq(mode(), 'n')
  feed('w')
  assert_eq(marks(), '1:3,2:3')
end)

-- ============================================================================
group('Q：保留原生行为，不自动开 follow-mode')
-- ============================================================================

run('Q 加的 cursor 不跟随 motion，但编辑仍级联', function()
  reset([[{'x y z','x y z'}]], '{1, 0}')
  feed('Q')
  feed('j')
  feed('Q')
  feed('0')
  feed('w')
  assert_eq(marks(), '1:0,2:0', 'motion must not cascade without follow-mode')
  feed('rZ')
  assert_eq(lines(), 'Z y z|Z Z z')
end)

-- ============================================================================
group('<M-n>：下方同列加 cursor + follow-mode')
-- ============================================================================

run('<M-n> 列对齐且跟随 motion', function()
  reset([[{'hello world','hi there','hello world'}]], '{1, 6}')
  feed('<M-n>')
  assert_eq(marks(), '1:6')
  feed('<M-n>')
  assert_eq(marks(), '1:6,2:6', 'second cursor aligns to the same column')
  feed('w')
  assert_eq(marks(), '2:0,3:0', 'follow-mode: w cascades')
end)

-- ============================================================================
group('\\A：一次选中所有匹配（visual-multi 的 Select All）')
-- ============================================================================

run('\\A 选中全部匹配，且不重复计数 primary', function()
  reset([[{'foo bar','x foo baz','foo qux','foo quux','foo corge'}]], '{3, 0}')
  feed('\\A')
  -- 5 处匹配 → 4 个额外 cursor（primary 在其中一个位置上）
  assert_eq(marks(), '1:0,2:2,4:0,5:0')
  assert_eq(mode(), 'v', 'enters extend mode')
end)

run('\\A 后可以直接编辑全部匹配', function()
  reset([[{'foo bar','x foo baz','foo qux','foo quux','foo corge'}]], '{3, 0}')
  feed('\\A')
  esc()
  feed('ciwZZ')
  esc()
  assert_eq(lines(), 'ZZ bar|x ZZ baz|ZZ qux|ZZ quux|ZZ corge')
end)

run('\\A 幂等：连按不会增加 cursor', function()
  reset([[{'foo a','foo b','foo c','foo d'}]], '{1, 0}')
  feed('\\A')
  local first = marks()
  feed('\\A')
  feed('\\A')
  assert_eq(marks(), first, 'repeat \\A must not add cursors')
end)

run('\\A 唯一匹配时不加 cursor', function()
  reset([[{'solo here'}]], '{1, 0}')
  feed('\\A')
  assert_eq(marks(), '', 'no extra cursors for a unique word')
end)

run('\\A 支持 visual 选区（字面匹配）', function()
  -- 三行都以 "xy" 开头；从 visual 选 "xy" 后 \\A 应把其余两处也选上。
  reset([[{'xy foo xy','xy foo xy','xy bar xy'}]], '{1, 0}')
  feed('vll')
  feed('\\A')
  assert_eq(marks(), '2:0,3:0', 'the other two "xy" occurrences get cursors')
end)

-- ============================================================================
group('<C-l>：有 cursor 时清除（buffer-local，无 cursor 时不动）')
-- ============================================================================

--- 查询当前 n 模式 buffer-local <C-l> 是否存在。
local function cl_buflocal()
  return lua([[
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
      if (m.lhs or ''):lower() == '<c-l>' then
        return true
      end
    end
    return false
  ]])
end

run('<C-l> 清除 cursor；无 cursor 时不挂映射', function()
  reset([[{'a b','a b'}]], '{1, 0}')
  assert_eq(cl_buflocal(), false, 'no buffer-local <C-l> before any session')

  feed('Q')
  feed('j')
  assert_eq(lua([[return require('vim._core.mcursor').active()]]), true)
  assert_eq(cl_buflocal(), true, 'mounted while a session exists')

  feed(vim.api.nvim_replace_termcodes('<C-l>', true, false, true))
  assert_eq(marks(), '', '<C-l> clears the cursors')
  assert_eq(lua([[return require('vim._core.mcursor').active()]]), false, 'session ends')
  assert_eq(cl_buflocal(), false, 'mapping unmounted after the session ends')
end)

run('<C-l> 在 extend 模式（<C-n> 之后）也能清除', function()
  reset([[{'foo bar','foo bar','foo bar'}]], '{1, 0}')
  feed('<C-n>')
  feed('<C-n>')
  assert_eq(mode(), 'v', 'in extend mode')
  assert_eq(marks(), '1:0,2:0')
  feed(vim.api.nvim_replace_termcodes('<C-l>', true, false, true))
  assert_eq(mode(), 'n', 'leaves visual')
  assert_eq(marks(), '', '<C-l> clears from extend mode')
  assert_eq(cl_buflocal(), false, 'unmounted')
end)

run('无 cursor 时 <C-l> 保持原样（全局映射不受影响）', function()
  reset([[{'plain'}]], '{1, 0}')
  -- 模拟 keymaps.lua 的全局 <C-l> = <C-w>l
  lua([[vim.keymap.set('n', '<C-l>', '<C-w>l')]])
  assert_eq(cl_buflocal(), false)
  assert_eq(lua([[return vim.fn.maparg('<C-l>', 'n', false, true).rhs]]), '<C-w>l')
  -- 不该被我们改动
  feed(vim.api.nvim_replace_termcodes('<C-l>', true, false, true))
  assert_eq(lua([[return vim.fn.maparg('<C-l>', 'n', false, true).rhs]]), '<C-w>l')
  -- 清理全局映射（这是测试注入的）
  lua([[pcall(vim.keymap.del, 'n', '<C-l>')]])
end)

run('会话结束后还原被覆盖的原 buffer-local <C-l>', function()
  reset([[{'foo bar','foo bar'}]], '{1, 0}')
  -- 模拟 diff_preview 自己装的 buffer-local <C-l>
  lua([[vim.keymap.set('n', '<C-l>', function() end, { buffer = 0, nowait = true, silent = true, desc = 'diffpreview-move' })]])
  feed('<C-n>')
  assert_eq(cl_buflocal(), true, 'ours is mounted')
  feed(vim.api.nvim_replace_termcodes('<C-l>', true, false, true))
  assert_eq(marks(), '', 'cleared')
  -- 原来的应被还原
  local desc = lua([[
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
      if (m.lhs or ''):lower() == '<c-l>' then
        return m.desc or ''
      end
    end
    return 'none'
  ]])
  assert_eq(desc, 'diffpreview-move', 'original buffer-local <C-l> restored')
  -- 清理：这条是测试自己注入的，不是配置里的，否则会污染后面的用例。
  lua([[pcall(vim.keymap.del, 'n', '<C-l>', { buffer = 0 })]])
  lua([[pcall(vim.keymap.del, 'x', '<C-l>', { buffer = 0 })]])
end)

run('Q / <M-n> 也能挂载与卸载 buffer-local <C-l>', function()
  reset([[{'aaa bbb','ccc ddd','eee fff'}]], '{1, 0}')
  feed('Q')
  assert_eq(cl_buflocal(), true, 'Q mounts')
  feed(vim.api.nvim_replace_termcodes('<C-l>', true, false, true))
  assert_eq(cl_buflocal(), false, 'Q unmounts')

  feed('<M-n>')
  assert_eq(cl_buflocal(), true, '<M-n> mounts')
  feed(vim.api.nvim_replace_termcodes('<C-l>', true, false, true))
  assert_eq(cl_buflocal(), false, '<M-n> unmounts')
end)

run('末行 <M-n> 无 cursor 时不挂载', function()
  reset([[{'aaa bbb','ccc ddd'}]], '{2, 0}')
  feed('<M-n>')
  assert_eq(marks(), '', 'no cursor created')
  assert_eq(cl_buflocal(), false, 'nothing to mount')
end)

-- ============================================================================
group('<C-p> / <C-x>：Remove Region / Skip Region（visual-multi 语义）')
-- ============================================================================

--- 查询会话键是否挂载（buffer-local）。
local function session_key_mounted(k)
  return lua(([[
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
      if (m.lhs or ''):lower() == %q then return true end
    end
    return false
  ]]):format(k:lower()))
end

run('<C-p>/<C-x> 仅在会话期间挂载', function()
  reset([[{'foo bar','foo baz'}]], '{1, 0}')
  assert_eq(session_key_mounted('<C-p>'), false)
  assert_eq(session_key_mounted('<C-x>'), false)
  feed('Q')
  assert_eq(session_key_mounted('<C-p>'), true)
  assert_eq(session_key_mounted('<C-x>'), true)
  feed('<C-l>')
  vim.wait(60, function()
    return false
  end)
  assert_eq(session_key_mounted('<C-p>'), false)
  assert_eq(session_key_mounted('<C-x>'), false)
end)

run('<C-p> 删除当前 region（primary 换成另一个 cursor）', function()
  reset([[{'foo bar','foo baz','foo qux','foo quux'}]], '{1, 0}')
  feed('<C-n>')
  feed('<C-n>')
  feed('<C-n>')
  -- primary 在 foo4(4:0)，anchors=[1:0,2:0,3:0]
  assert_eq(marks(), '1:0,2:0,3:0')
  feed('<C-p>')
  -- 删掉最近的（靠近 primary 的）一个，primary 换成它
  assert_eq(#vim.split(marks(), ',', { plain = true }), 2, 'one region removed')
end)

run('<C-x> 跳过当前并前进到下一个匹配（anchor 不变）', function()
  reset([[{'foo bar','foo baz','foo qux','foo quux','foo corge'}]], '{1, 0}')
  feed('<C-n>') -- drops foo1, primary -> foo2
  assert_eq(marks(), '1:0')
  local c0 = cursor()
  feed('<C-x>')
  assert_eq(marks(), '1:0', 'anchor unchanged')
  assert_eq(cursor() ~= c0, true, 'primary advanced to the next match')
  feed('<C-x>')
  assert_eq(marks(), '1:0', 'anchor still unchanged')
end)

run('回归：@/ 是陈旧值时 <C-x> 仍能正确工作', function()
  -- 旧 bug：<C-n> 用 searchpos()，它**不写** @/；而 <C-x> 靠 @/ 找下一个。
  -- 于是 @/ 为空或陈旧时，<C-x> 直接报 "no more matches"。
  reset([[{'foo bar','foo baz','foo qux'}]], '{1, 0}')
  -- 先把 @/ 设成一个无关的旧值
  lua([[vim.fn.setreg('/', 'zzznotfound')]])
  feed('<C-n>')
  assert_eq(lua([[return vim.fn.getreg('/')]]), '\\<foo\\>', '<C-n> must record the pattern in @/')
  feed('<C-x>')
  -- 应前进到 foo3（不报 no more matches）
  assert_eq(marks(), '1:0', 'anchor unchanged')
  assert_eq(cursor(), '{ 3, 2 }', '<C-x> advanced using the recorded pattern')
end)

run('<C-x> 找不到更多匹配时不动并提示', function()
  reset([[{'foo bar','foo baz'}]], '{1, 0}')
  feed('<C-n>') -- primary -> foo2, anchor foo1
  local before = cursor()
  feed('<C-x>') -- no more after foo2
  assert_eq(cursor(), before, 'primary must not move')
  assert_eq(marks(), '1:0', 'anchors unchanged')
end)

run('会话结束后 <C-p>/<C-x> 还原成原映射', function()
  reset([[{'foo bar','foo baz'}]], '{1, 0}')
  lua([[vim.keymap.set('n', '<C-p>', function() end, { buffer = 0, desc = 'OLD-cp' })]])
  lua([[vim.keymap.set('n', '<C-x>', function() end, { buffer = 0, desc = 'OLD-cx' })]])
  feed('Q')
  feed('<C-l>')
  vim.wait(60, function()
    return false
  end)
  local got = lua([[
    local o = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
      if (m.lhs or ''):lower() == '<c-p>' or (m.lhs or ''):lower() == '<c-x>' then
        o[#o + 1] = (m.lhs or ''):lower() .. '=' .. tostring(m.desc)
      end
    end
    table.sort(o)
    return table.concat(o, ' ; ')
  ]])
  assert_eq(got, '<c-p>=OLD-cp ; <c-x>=OLD-cx', 'original mappings restored')
  lua([[pcall(vim.keymap.del, 'n', '<C-p>', { buffer = 0 })]])
  lua([[pcall(vim.keymap.del, 'n', '<C-x>', { buffer = 0 })]])
end)

-- ============================================================================
group('git 操作保护：会话中禁用 reset 类操作')
-- ============================================================================

--- 查询某条 buffer-local 映射的 desc（不存在则 nil）。
--- 注意：nvim_buf_get_keymap 返回的 lhs 已展开 leader（`,gu`），不是 `<leader>gu`。
local function gu_desc()
  return lua([[
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
      if (m.lhs or ''):lower() == ',gu' then
        return m.desc or ''
      end
    end
    return 'NONE'
  ]])
end

run('有 cursor 时 <leader>gu 被接管（不执行 reset）', function()
  reset([[{'a b','a b'}]], '{1, 0}')
  -- 装一个和 gitsigns 同形的 buffer-local <leader>gu（本测试不依赖 git）
  lua([[vim.keymap.set('n', '<leader>gu', function() _G.__hit = true end, { buffer = 0, desc = 'fake-reset' })]])
  lua([[pcall(vim.keymap.set, 'n', '<leader>gC', function() end, { buffer = 0, desc = 'fake-reset-buf' })]])

  feed('Q')
  local armed = gu_desc()
  assert_eq(armed ~= 'NONE', true, 'gu mapping exists while a session is active')
  -- 按下不应执行原回调
  lua([[_G.__hit = false]])
  feed(',gu')
  assert_eq(lua([[return _G.__hit]]), false, 'original reset callback must NOT run')
end)

run('会话结束后 <leader>gu 还原成原映射', function()
  -- 上一条用例留下了活会话，先退出（会触发还原）
  feed('<C-l>')
  vim.wait(60, function()
    return false
  end)
  assert_eq(gu_desc(), 'fake-reset', 'original mapping restored after C-l')
  lua([[pcall(vim.keymap.del, 'n', '<leader>gu', { buffer = 0 })]])
  lua([[pcall(vim.keymap.del, 'n', '<leader>gC', { buffer = 0 })]])
end)

run('guard = false 时不接管', function()
  reset([[{'a b','a b'}]], '{1, 0}')
  lua([[require('lu5je0.ext.multicursor').opts.guard = false]])
  lua([[vim.keymap.set('n', '<leader>gu', function() _G.__hit2 = true end, { buffer = 0, desc = 'fake-reset' })]])
  feed('Q')
  assert_eq(gu_desc(), 'fake-reset', 'must not override when guard is off')
  lua([[require('lu5je0.ext.multicursor').opts.guard = true]])
  feed('<C-l>')
end)

-- ============================================================================

group('无匹配')
-- ============================================================================

run('没有下一个匹配时不加 cursor、不移动光标', function()
  reset([[{'alpha','beta'}]], '{1, 0}')
  feed('<C-n>')
  assert_eq(marks(), '')
  assert_eq(cursor(), '{ 1, 0 }')
end)

-- ============================================================================

-- 直接停掉子进程（不要用 :qa!：--embed 会先关掉 channel，导致 rpcrequest 报 E5113）。
vim.fn.jobstop(chan)

print(('\n%d passed, %d failed'):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
