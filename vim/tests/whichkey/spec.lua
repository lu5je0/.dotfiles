-- which-key `<leader>` 触发器端到端测试（**非 headless**）。
-- Usage: cd vim && nvim --headless -u NONE -l tests/whichkey/spec.lua
--
-- 为什么不用 --headless 跑 child：
--   which-key 的触发依赖正常的启动事件（UIEnter / VeryLazy）和真实的按键路径。
--   `--embed --headless` 下没有 UI，UIEnter 不完整，而且一旦 nvim_ui_attach
--   又会因为 RPC 客户端不处理 redraw 而让 child 退出。
--   这里用 `--listen <sock>` + pty：child 是一个货真价实的 TUI（UIEnter 自然触发），
--   RPC 走 socket，既能读状态也能 nvim_input 发真实按键。
--
-- 回归目标（本文件第二、三组断言）：
--   某个 lazy.nvim 插件 spec 若把 `keys` 写成裸 `<leader>`（例如 `keys = { ',' }`），
--   lazy.nvim 会在全局建一个 `<leader>` proxy。which-key 的 triggers.lua:is_mapped()
--   看到 `<leader>` 已被非 which-key 映射占用，就会**拒绝安装**自己的 `<leader>` 触发器，
--   于是第一次按 `<leader>` 只是 lazy 自删+加载插件，不弹 which-key。
--   这里直接断言「不存在 lazy.nvim 的 <leader> proxy」+「which-key 触发器已安装」+「第一次按就弹」。

local pass, fail = 0, 0
local function check(name, ok, extra)
  if ok then
    pass = pass + 1
    print('  ok   ' .. name)
  else
    fail = fail + 1
    print('  FAIL ' .. name .. (extra and ('  -- ' .. tostring(extra)) or ''))
  end
end

local function nvim_bin()
  if vim.env.NVIM_TEST_BIN and vim.env.NVIM_TEST_BIN ~= '' then
    return vim.env.NVIM_TEST_BIN
  end
  return vim.v.progpath
end

-- child 也依赖本仓库配置（lazy.nvim / which-key）能被正常加载。
local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
local rtp = repo_root .. '/vim'

local sock = vim.fn.tempname() .. '.sock'
local chan = vim.fn.jobstart(
  { nvim_bin(), '--listen', sock, '--cmd', 'set rtp+=' .. rtp },
  {
    pty = true,
    env = { TERM = 'xterm-256color' },
    -- 必须持续排空 pty，否则 TUI 输出写满 pty buffer，child 会阻塞在启动阶段。
    on_stdout = function() end,
  }
)

local function cleanup()
  pcall(function()
    local rpc = vim.fn.sockconnect('pipe', sock, { rpc = true })
    vim.rpcrequest(rpc, 'nvim_command', 'qa!')
  end)
  vim.wait(200, function()
    return false
  end)
  pcall(vim.fn.jobstop, chan)
  pcall(os.remove, sock)
end

local ready = vim.wait(15000, function()
  return vim.uv.fs_stat(sock) ~= nil
end, 50)
if not ready then
  print('FAIL: child nvim 没能在 15s 内开出 socket')
  cleanup()
  os.exit(1)
end

local rpc = vim.fn.sockconnect('pipe', sock, { rpc = true })
local function req(method, ...)
  return vim.rpcrequest(rpc, method, ...)
end
local function q(code)
  local ok, r = pcall(req, 'nvim_exec_lua', code, {})
  return ok, r
end
local function feed(keys)
  pcall(req, 'nvim_input', keys)
end

-- 等 which-key 完成加载。若本机没装/加载不了，SKIP（和 multicursor spec 的约定一致）。
local loaded = vim.wait(20000, function()
  local ok, v = q([[return package.loaded['which-key'] ~= nil]])
  return ok and v == true
end, 100)
if not loaded then
  print('SKIP: which-key 未加载（lazy.nvim/插件可能未安装）')
  cleanup()
  os.exit(0)
end

-- which-key 的触发器由 50ms 定时器 → Buf.get → Triggers.schedule 异步安装，等它稳定。
vim.wait(2000, function()
  return false
end)

print('which-key <leader> 触发器')

-- 1) 全局 `<leader>` 上不能有 lazy.nvim 的 proxy。
local _, gmaps = q([[
  local out = {}
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    if m.lhs == ',' then
      local src = ''
      if type(m.callback) == 'function' then
        local i = debug.getinfo(m.callback, 'S')
        src = tostring(i and i.source)
      end
      out[#out + 1] = { desc = m.desc, rhs = m.rhs, src = src }
    end
  end
  return out
]]) --[[@as table]]
local lazy_proxy = false
for _, m in ipairs(gmaps) do
  if m.src and m.src:find('lazy/core/handler/keys', 1, true) then
    lazy_proxy = true
  end
end
check('全局 <leader> 上没有 lazy.nvim proxy', not lazy_proxy, vim.inspect(gmaps))

-- 2) which-key 自己的 `<leader>` 触发器已安装（buffer-local）。
local _, bmaps = q([[
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, 'n')) do
    if m.lhs == ',' then
      out[#out + 1] = { desc = m.desc, rhs = m.rhs, cb = type(m.callback) }
    end
  end
  return out
]]) --[[@as table]]
local has_trigger = false
for _, m in ipairs(bmaps) do
  if m.desc and m.desc:find('which-key-trigger', 1, true) then
    has_trigger = true
  end
end
check('which-key <leader> 触发器已安装', has_trigger, vim.inspect(bmaps))

-- 2.5) 防回归：telescope 仍能通过真实键位懒加载（不能再退回裸 <leader>）。
local _, ff_present = q([[
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    if m.lhs == ',ff' then return true end
  end
  return false
]])
check('telescope 仍可通过 <leader>ff 懒加载', ff_present == true)

-- 3) 第一次按 `<leader>` 就应弹出 which-key（等过 delay=1000ms）。
local function has_popup()
  local ok, r = q([[
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'wk' then
        return true
      end
    end
    return false
  ]])
  return ok and r == true
end
check('按键前没有 which-key 弹窗', not has_popup())
feed(',')
local popped = vim.wait(3000, has_popup, 100)
check('第一次按 <leader> 弹出 which-key', popped)
feed(vim.api.nvim_replace_termcodes('<Esc>', true, false, true))

cleanup()
print(string.format('%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
