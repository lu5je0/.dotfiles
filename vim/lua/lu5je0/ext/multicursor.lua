-- 原生 multicursor（Neovim 0.13+，:help multicursor）的按键适配。
--
-- 0.13 起 multicursor 是内建能力，不再是 vim-visual-multi 那种插件。这里保留 Ctrl-N
-- 逐个加匹配的入口，但使用更稳定的原生 normal-mode cursor 语义：
--
--   <C-n>  在光标下的词（或 visual 选中的文本）及下一个匹配处放 cursor；连按逐个加，
--          并开启 follow-mode（q=），所以 w/b/j/k 这类纯 motion 会在所有 cursor 重放。
--          替换每个词使用原生 operator+motion，例如 ciw。
--   \A     一次在当前词/选区的所有匹配处放置 cursor。
--   <M-n>  在当前行下方同列加一个 cursor（列对齐），并开启 follow-mode。
--   <C-l>  有 multicursor 时清除光标（buffer-local，仅在有 cursor 时挂载）；
--          没有 cursor 时 <C-l> 完全不受影响（仍是你的切窗口 / diff_preview 映射）。
--
-- 其余原生键位保留默认：
--   Q        在当前位置切换一个 cursor（注意：原生 Q 会关闭 follow-mode）
--   [count]Q 上次搜索的每个匹配处放 cursor（1Q = 全部）
--   gQ       恢复上次清除的 cursors
--   ]C / [C  跳下 / 上一个 cursor
--   g CTRL-A 每个 cursor 插入递增数字
--
-- 只在支持该能力的版本上生效（vim.api.nvim_mcursor 存在）。0.12 上彻底 no-op，
-- 由 vim-visual-multi 负责同样的键位（见 plugins.lua 的 enabled 门控）。

local M = {}

-- 可配置项（先默认，setup(opts) 可覆盖）。
--
--   guard          是否在 multicursor 会话中拦截会改 buffer 的 git 操作（见下）
--   guarded_keys   会被拦截的 buffer-local 映射；默认 reset 类操作：
--                  reset_hunk/reset_buffer 会 nvim_buf_set_lines()，而整行替换会推动
--                  multicursor 的 anchor extmark（right_gravity）漂到下一行，导致
--                  cursor 合并/错位。stage/unstage 只写 git index，不动 buffer，不需拦。
--   guard_message  拦截时的提示（nil 则不提示）；可以是 string 或 fun()
M.opts = {
  guard = true,
  guarded_keys = { '<leader>gu', '<leader>gC' },
  guard_message = 'multicursor: git reset is disabled with multiple cursors (<C-l> to exit)',
}

-- 不支持时（0.12）也导出 setup，让 ext-config 可以无条件调用。
M.setup = function() end

if type(vim.api.nvim_mcursor) ~= 'function' then
  return M
end

local mc = require('vim._core.mcursor')

local ns = vim.api.nvim_create_namespace('nvim.multicursor')
local session_patterns = {} ---@type table<integer, string>

local function clear_session_state(buf)
  session_patterns[buf] = nil
end

--- 在移动 primary 前关掉 follow；移动完成后由调用方重新开启。
local function pause_follow()
  vim.cmd('normal! 2q=')
end

--- 清除当前 buffer 的所有 multicursor（等价原生 CTRL-L 的效果部分）。
--- 清空 namespace 会同时结束会话并关闭 follow-mode。
local function clear()
  clear_session_state(vim.api.nvim_get_current_buf())
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

--- 从光标之后开始搜索 pattern，返回 {row, col_1based}；不移动光标、不改变视图。
--- @param pat string
--- @return integer[]|nil
local function find_next(pat, flags)
  local view = vim.fn.winsaveview()
  local pos = vim.fn.searchpos(pat, flags or 'W') -- W: 不环绕
  vim.fn.winrestview(view)
  if pos[1] == 0 then
    return nil
  end
  return pos
end

--- 收集整个 buffer 里 pattern 的所有匹配，返回 {row, col_0based} 列表。
--- 不移动光标、不改变视图。
--- @param pat string
--- @return integer[][]
local function find_all(pat)
  local view = vim.fn.winsaveview()
  local cur = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local positions = {}
  local pos = vim.fn.searchpos(pat, 'cW')
  while pos[1] ~= 0 do
    positions[#positions + 1] = { pos[1], pos[2] - 1 }
    pos = vim.fn.searchpos(pat, 'W')
  end
  vim.fn.winrestview(view)
  vim.api.nvim_win_set_cursor(0, cur)
  return positions
end

--- 把当前位置留成一个 cursor，primary 移到目标位置。
---
--- 移光标前先关 follow，避免上游 `follow && map_moved && !Visual.active` 触发级联；
--- 调用方应在移完后重新打开 follow。
--- @param pos integer[] {row, col_1based} 目标位置
--- @param orig integer[]? {row, col_0based} 要保留的位置；缺省用当前光标
local function place_cursor(pos, orig)
  pause_follow()
  orig = orig or vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_mcursor(0, { orig[1], orig[2] })
  vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] - 1 })
end

--- visual 选区的起始位置（左上角）。
--- 注意：退出 visual 后窗口光标停在「活跃端」而不是选区开头，所以必须显式算起始位置，
--- 否则留下来的 cursor 会落在词中间，和 primary 不在同一列。
--- 返回 {row_1based, col_0based}（与 nvim_mcursor / nvim_win_get_cursor 一致）。
--- @return integer[]
local function visual_start()
  local a = vim.fn.getpos('v')
  local b = vim.fn.getpos('.')
  if vim.fn.mode() == 'V' then
    return { math.min(a[2], b[2]), 0 }
  end
  -- charwise / blockwise：取最左上的端点
  if a[2] < b[2] or (a[2] == b[2] and a[3] <= b[3]) then
    return { a[2], a[3] - 1 }
  end
  return { b[2], b[3] - 1 }
end

--- 把 pattern 写进搜索寄存器 `@/`。
---
--- 为什么必须做：<C-n>/<\A> 内部用 `vim.fn.searchpos()`，它**不**更新 `@/`。
--- 而 `<C-x>`（Skip）需要靠 `@/` 找下一个匹配；不写的话，`@/` 是空或是十年前的旧值，
--- `<C-x>` 就会报 "no more matches"（用户报告过）。写进去后 `<C-n>` 之后直接 `1Q` 也能全选。
---
--- 注意：不主动开 `hlsearch`（只写寄存器），避免把高亮强加给不想看到的人；
--- 要清高亮用 `<C-l>`（它本来就带 nohlsearch）。
--- @param pat string
local function remember_pattern(pat)
  vim.fn.setreg('/', pat)
  vim.fn.histadd('/', pat)
end

--- 光标下整词的搜索 pattern（\<word\>），空词返回 nil。
--- @return string|nil
local function word_pattern()
  local word = vim.fn.expand('<cword>')
  if word == '' then
    return nil
  end
  -- expand('<cword>') 返回的是「词」，不含正则元字符，但仍转义以防特殊字符类词。
  return '\\<' .. vim.fn.escape(word, '\\/.*$^~[]') .. '\\>'
end

--- visual 选区（可能跨行）里的文本，作为字面 pattern；跨行时退化为光标下的词。
--- @return string|nil
local function visual_pattern()
  -- 注意：在 x-mode mapping 里 vim.fn.visualmode() 返回空串（已结束选区），
  -- 必须从 vim.fn.mode() 推导当前 v/V/<C-v> 类型。
  local m = vim.fn.mode()
  local vmode = m == 'V' and 'V' or m == '\22' and '\22' or 'v'
  local first = vim.fn.getpos('v')
  local last = vim.fn.getpos('.')
  local region = vim.fn.getregion(first, last, { type = vmode })
  local text = table.concat(region, '\n')
  if text == '' then
    return nil
  end
  if text:find('\n', 1, true) then
    -- 多行选区的字面匹配意义不大，退化为光标下的词。
    return nil
  end
  return '\\V' .. vim.fn.escape(text, '\\/')
end

--- <C-n>：把当前位置留成一个 normal-mode cursor，primary 跳到下一个匹配，
--- 并开启 follow-mode。后续按 `ciw` 等原生 operator+motion 同时编辑各 cursor。
---
--- 整体必须 schedule：函数最终停在 normal mode 且开启 follow；若在当前 typed CmdAtom 内
--- 移动光标，上游会把整个 mapping LHS replay 到每个 cursor，导致数量级联。
local busy = false

local function ctrl_n()
  if busy then
    return
  end
  local visual = vim.fn.mode():find('[vV\22]') ~= nil
  local buf = vim.api.nvim_get_current_buf()
  local pat = mc.active() and session_patterns[buf] or (visual and (visual_pattern() or word_pattern()) or word_pattern())
  if not pat then
    return
  end
  remember_pattern(pat)
  local orig = visual and visual_start() or nil

  busy = true
  vim.schedule(function()
    local pos = find_next(pat)
    if not pos then
      busy = false
      vim.notify('multicursor: no next match', vim.log.levels.INFO)
      return
    end
    if visual then
      vim.cmd('normal! ' .. vim.keycode('<Esc>'))
    end
    place_cursor(pos, orig)
    vim.cmd('normal! 1q=')
    session_patterns[buf] = pat
    busy = false
  end)
end

--- \\A：一次在当前词（或 visual 选区文本）的所有匹配处放置 normal-mode cursor。
--- primary 取离原光标最近的那个匹配，避免跳远。
local function select_all()
  if busy then
    return
  end
  local visual = vim.fn.mode():find('[vV\22]') ~= nil
  local buf = vim.api.nvim_get_current_buf()
  local pat = mc.active() and session_patterns[buf] or (visual and (visual_pattern() or word_pattern()) or word_pattern())
  if not pat then
    return
  end
  remember_pattern(pat)
  local cur = vim.api.nvim_win_get_cursor(0)

  busy = true
  vim.schedule(function()
    if visual then
      vim.cmd('normal! ' .. vim.keycode('<Esc>'))
    end
    local positions = find_all(pat)
    if #positions == 0 then
      busy = false
      vim.notify('multicursor: no matches', vim.log.levels.INFO)
      return
    end

    local best = positions[1]
    local bestd = math.huge
    for _, p in ipairs(positions) do
      local d = math.abs(p[1] - cur[1]) * 10000 + math.abs(p[2] - cur[2])
      if d < bestd then
        best, bestd = p, d
      end
    end

    pause_follow()
    for _, p in ipairs(positions) do
      if not (p[1] == best[1] and p[2] == best[2]) then
        vim.api.nvim_mcursor(0, { p[1], p[2] })
      end
    end
    vim.api.nvim_win_set_cursor(0, best)
    vim.cmd('normal! 1q=')
    session_patterns[buf] = pat
    busy = false
  end)
end

--- 会话里所有 cursor 的位置：primary（窗口光标）+ 各 anchor。
--- anchor 是 0-based（extmark 语义），这里统一转成 {row_1based, col_0based}。
--- @return integer[][]
local function all_cursors()
  local out = { vim.api.nvim_win_get_cursor(0) }
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})) do
    out[#out + 1] = { m[2] + 1, m[3] }
  end
  return out
end

--- 删除当前 cursor（primary 所在位置），并把 primary 换成剩下的另一个 cursor。
---
--- 上游只有「加 cursor」的 API，删除要靠删 anchor extmark；而 primary 本身不是 extmark，
--- 所以「删当前」的实现是：找一个 anchor（优先与 primary 同位置，否则取最近的）删掉，
--- 并把窗口光标移到那个位置——效果就是「当前 region 被移除，primary 换成另一个」。
---
--- @return boolean removed
local function remove_current()
  if not mc.active() then
    -- 只剩 primary（没有额外 cursor）时，直接结束会话。
    vim.cmd('normal! ' .. vim.keycode('<Esc>'))
    return false
  end

  local cur = vim.api.nvim_win_get_cursor(0)
  local pick, bestd = nil, math.huge
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})) do
    local row, col = m[2] + 1, m[3]
    if row == cur[1] and col == cur[2] then
      pick, bestd = m, -1
      break
    end
    local d = math.abs(row - cur[1]) * 10000 + math.abs(col - cur[2])
    if d < bestd then
      pick, bestd = m, d
    end
  end
  if not pick then
    return false
  end

  if vim.fn.mode():find('[vV\22]') then
    vim.cmd('normal! ' .. vim.keycode('<Esc>'))
  end
  pause_follow()
  vim.api.nvim_buf_del_extmark(0, ns, pick[1])
  vim.api.nvim_win_set_cursor(0, { pick[2] + 1, pick[3] })
  if mc.active() then
    vim.cmd('normal! 1q=')
  else
    clear_session_state(vim.api.nvim_get_current_buf())
  end
  return true
end

--- <C-p>：删除当前 region（visual-multi 的 Remove Region）。
local function remove_region()
  if busy then
    return
  end
  busy = true
  vim.schedule(function()
    remove_current()
    busy = false
  end)
end

--- <C-x>：跳过当前 region（primary 所在处）并选下一个匹配。
---
--- 语义（visual-multi 的 Skip Region）：primary 当前位置被丢弃，primary 前进到下一个匹配；
--- 已有 anchor 不变。所以总 region 数不变。
---   例：anchors=[foo1], primary=foo2  →  skip  →  anchors=[foo1], primary=foo3
--- 找不到下一个时保持现状并提示（不环绕）。
local function skip_region()
  if busy then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local pat = session_patterns[buf] or vim.fn.getreg('/')
  if pat == '' then
    vim.notify('multicursor: no search pattern', vim.log.levels.INFO)
    return
  end

  busy = true
  vim.schedule(function()
    local c = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_buf_get_lines(0, c[1] - 1, c[1], true)[1] or ''
    local view = vim.fn.winsaveview()
    vim.api.nvim_win_set_cursor(0, { c[1], math.min(c[2] + 1, #line) })
    local pos = vim.fn.searchpos(pat, 'W')
    vim.fn.winrestview(view)
    vim.api.nvim_win_set_cursor(0, c)

    if pos[1] == 0 then
      busy = false
      vim.notify('multicursor: no more matches', vim.log.levels.INFO)
      return
    end

    if vim.fn.mode():find('[vV\22]') then
      vim.cmd('normal! ' .. vim.keycode('<Esc>'))
    end
    pause_follow()
    vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] - 1 })
    if mc.active() then
      vim.cmd('normal! 1q=')
    end
    busy = false
  end)
end

--- <M-n>：在下方同列加一个 cursor（保持 virtual column），并开启 follow-mode。
---
--- 与 `<C-n>` 同一套原理：先关 follow -> 移光标 -> 再开 follow，
--- 避免命中 `follow && map_moved && !Visual.active` 级联。这里额外包一层 vim.schedule：
--- `<M-n>` 不经 visual 模式，schedule 能让整块不落进当次 CmdAtom，实测最稳。
local function alt_n()
  if busy then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local next_line = cur[1] + 1
  if next_line > vim.api.nvim_buf_line_count(0) then
    return
  end

  local vcol = vim.fn.virtcol('.')
  busy = true
  vim.schedule(function()
    pause_follow()
    local col = vim.fn.virtcol2col(0, next_line, vcol)
    if col <= 0 then
      -- 下一行更短：落到该行行尾。
      local text = vim.api.nvim_buf_get_lines(0, next_line - 1, next_line, true)[1] or ''
      col = #text + 1
    end
    vim.api.nvim_mcursor(0, { cur[1], cur[2] })
    vim.api.nvim_win_set_cursor(0, { next_line, col - 1 })
    vim.cmd('normal! 1q=')
    busy = false
  end)
end

--- <C-l>：multicursor 会话存在时清除光标（并 nohlsearch）。
---
--- 设计：不像 <Esc> 那样永久/懒挂载全局映射，而是**只在与本 buffer 有 cursor 时**
--- 挂一个 buffer-local 映射；会话结束就删掉，并把可能被我们覆盖的原 buffer-local
--- <C-l> 还原（例如 sidebar 的 diff_preview 自己就装了 buffer-local <C-l>）。
--- 没有 cursor 时根本不挂，所以 buffer 里的 <C-l> 还是原来的：
---   - 全局 <C-l> = <C-w>l（keymaps.lua）
---   - diff_preview 等自己的 buffer-local <C-l>
--- buffer-local 优先于全局，所以只要挂了就一定命中我们。
local CL_KEY = '<C-l>'
local cl_buf = nil ---@type integer? 当前挂着映射的 buffer
local cl_saved = nil ---@type table? 被我们覆盖掉的原 buffer-local <C-l>

--- 把 lhs 里的 `<leader>` 展开成实际按键（mapleader 默认是 `\`，本仓库是 `,`）。
--- `vim.keymap.set` 接受 `<leader>xxx`，但 `nvim_buf_get_keymap()` 返回的是展开后的形式，
--- 所以比较前必须规范化。
--- @param lhs string
--- @return string
local function expand_leader(lhs)
  if not lhs:find('<leader>', 1, true) then
    return lhs
  end
  local leader = vim.g.mapleader
  if type(leader) ~= 'string' or leader == '' then
    leader = '\\'
  end
  return (lhs:gsub('<[Ll]eader>', vim.pesc(leader)))
end

--- 把 nvim_buf_get_keymap 返回的映射重新注册回去（用于还原）。
--- 注意：注册时用展开 leader 后的 key（与 capture 一致）。
--- @param buf integer
--- @param key string 要还原的 lhs（可为 `<leader>xx`）
--- @param m table
--- @param mode string
local function restore_map(buf, key, m, mode)
  local opts = {
    buffer = buf,
    nowait = m.nowait == 1,
    silent = m.silent == 1,
    desc = m.desc,
  }
  local lhs = expand_leader(key)
  if m.callback then
    vim.keymap.set(mode, lhs, m.callback, opts)
  elseif m.rhs and m.rhs ~= '' then
    vim.keymap.set(mode, lhs, m.rhs, opts)
  end
end

--- 取 buffer 里已有的某条 buffer-local 映射（没有则 nil）。
--- nvim_buf_get_keymap() 返回的 lhs 是规范化的：
---   - 大小写规范化（`<C-l>` -> `<C-L>`），所以两边都 lowercase；
---   - **`<leader>` 会被展开**（`<leader>gu` -> `,gu`），所以要先展开再比。
--- 坑：不处理 leader 展开时就永远匹配不到（gitsigns/diff-base 的 gu 都是 `<leader>` 定义）。
--- @param buf integer
--- @param lhs string
--- @param mode string
--- @return table?
local function capture_buf_map(buf, lhs, mode)
  local want = expand_leader(lhs):lower()
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if (m.lhs or ''):lower() == want then
      return m
    end
  end
  return nil
end

function unmount_cl(buf_override, saved_override)
  local buf = buf_override or cl_buf
  local saved = saved_override or cl_saved
  if buf == nil then
    return
  end
  cl_buf, cl_saved = nil, nil
  if vim.api.nvim_buf_is_valid(buf) then
    for _, mode in ipairs { 'n', 'x' } do
      pcall(vim.keymap.del, mode, CL_KEY, { buffer = buf })
    end
    if saved and saved.buf == buf then
      restore_map(buf, CL_KEY, saved.map, saved.mode)
    end
  end
end
--- 会话期间额外挂载的 buffer-local 键（<C-p>/<C-x>）。
--- 它们只在会话中有意义，所以和 <C-l> 一样做成懒挂载 + 退出时还原。
local SESSION_KEYS = {
  { key = '<C-p>', fn = remove_region, desc = 'multicursor: remove region' },
  { key = '<C-x>', fn = skip_region, desc = 'multicursor: skip region' },
}
local session_saved = {} ---@type table<string, table?> lhs -> 被覆盖的原 buffer-local 映射
local session_buf = nil ---@type integer? 当前挂着会话键的 buffer

--- cl_action 触发的延迟卸载状态（它自己不能删映射，交给 sync_cl_map）。
local pending_unmount = nil ---@type table?

local function unmount_session_keys(buf_override, saved_override)
  local buf = buf_override or session_buf
  local saved_all = saved_override or session_saved
  session_buf, session_saved = nil, {}
  if buf == nil then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  for _, item in ipairs(SESSION_KEYS) do
    pcall(vim.keymap.del, { 'n', 'x' }, item.key, { buffer = buf })
    local saved = saved_all[item.key]
    if saved then
      restore_map(buf, item.key, saved.map, saved.mode)
    end
  end
end

local function mount_session_keys(buf)
  if session_buf == buf then
    return
  end
  session_buf = buf
  for _, item in ipairs(SESSION_KEYS) do
    local existing = capture_buf_map(buf, item.key, 'n')
    session_saved[item.key] = existing and { map = existing, mode = 'n' } or nil
    local opts = { buffer = buf, nowait = true, silent = true, desc = item.desc }
    vim.keymap.set('n', item.key, item.fn, opts)
    vim.keymap.set('x', item.key, item.fn, opts)
  end
end
local guarded_buf = nil ---@type integer?
local guarded_saved = {} ---@type table<string, table> lhs -> {map=..., mode=...}

--- 拦截时的提示。
local function guard_notify()
  local msg = M.opts.guard_message
  if type(msg) == 'function' then
    msg = msg()
  end
  if msg then
    vim.notify(msg, vim.log.levels.INFO)
  end
end

local function unmount_guard(buf_override, saved_override)
  local buf = buf_override or guarded_buf
  local saved_all = saved_override or guarded_saved
  guarded_buf, guarded_saved = nil, {}
  if buf == nil or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  for lhs, saved in pairs(saved_all) do
    pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
    if saved then
      restore_map(buf, lhs, saved.map, saved.mode)
    end
  end
end

--- 同时提供 n/x 映射：本模块以 normal-mode cursor 为主，但仍允许从用户自己的 visual
--- 选区开始会话；两种模式都可直接清除。
---
--- 注意顺序：先 unmount_cl() 再 clear()。因为 clear() 会触发上游 enable(false)
--- → sync_cl_map → unmount_cl，那时 cl_buf 已被置 nil，cl_saved 已在第一次
--- unmount 中被清掉，还原就丢了。先手动卸载并还原，再 clear。
local function cl_action()
  vim.cmd('normal! ' .. vim.keycode('<Esc>'))

  -- 关键：**不能在本回调里删正在执行的那个 <C-l> 映射**。实测在映射回调中
  -- vim.keymap.del 掉自己会让回调立即中止（后面的语句不再执行）。
  -- 所以这里只做「清除 + 记住要还原什么」，实际的 del/restore 全部交给
  -- clear() 触发的 enable(false) → scheduled sync_cl_map（它不在本回调栈上）。
  --
  -- 但 enable(false) 里 sync_cl_map 已经看不到 cl_buf/session_buf（已被置 nil），
  -- 所以先把它们「寄存」到 pending，让 sync_cl_map 用后再清。
  if mc.active() then
    pending_unmount = {
      cl = cl_buf and { buf = cl_buf, saved = cl_saved } or nil,
      session = session_buf and { buf = session_buf, saved = session_saved } or nil,
      guard = guarded_buf and { buf = guarded_buf, saved = guarded_saved } or nil,
    }
    cl_buf, cl_saved = nil, nil
    session_buf, session_saved = nil, {}
    guarded_buf, guarded_saved = nil, {}
    clear()
    vim.cmd('nohlsearch')
  else
    -- 没有会话（映射不该挂着）；交给下一拍清掉。
    vim.schedule(sync_cl_map)
  end
end

local function mount_cl(buf)
  if cl_buf == buf then
    return
  end
  unmount_cl()
  cl_buf = buf
  -- 先存下原有的（可能是 diff_preview 等装的），卸载时还原。只存 n 模式的那条。
  local existing = capture_buf_map(buf, CL_KEY, 'n')
  cl_saved = existing and { buf = buf, map = existing, mode = 'n' } or nil
  local opts = { buffer = buf, nowait = true, silent = true, desc = 'multicursor: clear cursors' }
  vim.keymap.set('n', CL_KEY, cl_action, opts)
  vim.keymap.set('x', CL_KEY, cl_action, opts)
end

-- ============================================================================
-- git 操作保护
-- ============================================================================
--
-- reset_hunk / reset_buffer（gitsigns 与 diff-base）会用 nvim_buf_set_lines() 整行替换
-- buffer 内容。而 multicursor 的 anchor 是 right_gravity 的 extmark：整行替换会让 anchor
-- 漂到下一行，然后与那里的 cursor 合并 → 表现为「按一下 <leader>gu 光标就少/乱」。
-- 实测最小复现（不涉任何配置）：
--     nvim_mcursor(0,{1,0}); nvim_mcursor(0,{2,0}); nvim_mcursor(0,{3,0})
--     nvim_buf_set_lines(0, 2, 3, false, {'x'})   -- anchors: 1:0,2:0,3:0 -> 1:0,2:0,4:0
-- 这是上游 extmark gravity 的边界问题（mc_mark_upd 用 right_gravity=true）。
--
-- 所以会话期间把这些键换成「不执行 + 提示」，退出后再还原成原有映射。
-- stage/unstage 只写 git index、不动 buffer，不在保护名单里。

local function mount_guard(buf)
  if guarded_buf == buf or not M.opts.guard then
    return
  end
  unmount_guard()
  guarded_buf = buf
  for _, lhs in ipairs(M.opts.guarded_keys or {}) do
    local existing = capture_buf_map(buf, lhs, 'n')
    guarded_saved[lhs] = existing and { map = existing, mode = 'n' } or nil
    vim.keymap.set('n', lhs, guard_notify, {
      buffer = buf,
      nowait = true,
      silent = true,
      desc = 'multicursor: disabled (multiple cursors)',
    })
  end
end

--- 会话状态变化时同步 <C-l> 与 git 保护映射（当前 buffer）。
--- 用 `mc.active()` 判断；cursor 是 per-buffer 的，所以还要在 BufEnter 等边界重查。
local function sync_cl_map()
  -- 先消化 cl_action 寄存的待卸载状态（它自己不能在本回调里删映射，见 cl_action）。
  if pending_unmount then
    local p = pending_unmount
    pending_unmount = nil
    if p.cl then
      unmount_cl(p.cl.buf, p.cl.saved)
    end
    if p.session then
      unmount_session_keys(p.session.buf, p.session.saved)
    end
    if p.guard then
      unmount_guard(p.guard.buf, p.guard.saved)
    end
  end

  if mc.active() then
    local buf = vim.api.nvim_get_current_buf()
    -- 换 buffer（cursor 是 per-buffer 的）：旧 buffer 的会话键要先还原。
    if session_buf and session_buf ~= buf then
      unmount_session_keys(session_buf)
    end
    mount_cl(buf)
    mount_session_keys(buf)
    mount_guard(buf)
  else
    clear_session_state(vim.api.nvim_get_current_buf())
    unmount_session_keys()
    unmount_cl()
    unmount_guard()
  end
end
--- MCursor 高亮：原生默认 link 到 CurSearch（edge 下是蓝色实底，本身可见），
--- 这里在继承该配色的基础上加粗，让「额外 cursor」和普通搜索高亮能区分。
--- MCursorVisual（选区）保持原生默认 link Visual，不动。
local function apply_hl()
  local ok, cs = pcall(vim.api.nvim_get_hl, 0, { name = 'CurSearch', link = false })
  if not ok then
    return
  end
  vim.api.nvim_set_hl(0, 'MCursor', { fg = cs.fg, bg = cs.bg, bold = true })
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend('force', M.opts, opts or {})
  apply_hl()
  local group = vim.api.nvim_create_augroup('lu5je0_multicursor', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = apply_hl })

  -- 会话开始/结束：同步 buffer-local <C-l> 与 git 保护映射。
  -- enable() 是上游唯一在会话边界调用的 Lua 入口；但它在 mc_cleanup 里调用时
  -- 会话状态可能尚未定下来，所以统一延后一拍用 mc.active() 重新判定。
  local mc_core = require('vim._core.mcursor')
  local orig_enable = mc_core.enable
  mc_core.enable = function(enable)
    orig_enable(enable)
    vim.schedule(sync_cl_map)
  end

  -- 兜底：cursor 是 per-buffer 的，换 buffer / 销毁时重查一次。
  vim.api.nvim_create_autocmd({ 'BufEnter' }, {
    group = group,
    callback = sync_cl_map,
  })
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
    group = group,
    callback = function(ev)
      session_patterns[ev.buf] = nil
      if cl_buf == ev.buf then
        cl_buf = nil
        cl_saved = nil
      end
      if guarded_buf == ev.buf then
        guarded_buf = nil
        guarded_saved = {}
      end
      if session_buf == ev.buf then
        session_buf = nil
        session_saved = {}
      end
    end,
  })

  vim.keymap.set({ 'n', 'x' }, '<C-n>', ctrl_n, { silent = true, desc = 'multicursor: add next match' })
  vim.keymap.set({ 'n', 'x' }, '\\A', select_all, { silent = true, desc = 'multicursor: select all matches' })
  vim.keymap.set('n', '<M-n>', alt_n, { silent = true, desc = 'multicursor: add cursor below' })
end

return M
