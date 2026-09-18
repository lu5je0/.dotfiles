# Neovim 配置工作指引

## 适用范围
- 本文件适用于 `vim/` 目录下的 Neovim 配置、测试、补丁与本地依赖约定。
- 如果任务同时涉及仓库根目录其他组件，遵循就近原则：`vim/` 内改动优先参考本文件，跨目录联动再补充阅读对应目录文档。
- 如果任务同时涉及 `submodule/tui-bridge` 和 `vim/`，还需阅读 `submodule/tui-bridge/AGENTS.md`。

## 维护约定
- 修改配置装配方式、核心目录职责、测试入口、补丁流程、`tui-bridge` 接入方式时，必须同步更新本文件。
- 只要 AI 改动了本文件已声明的事实、规则、目录职责、验证方式或联动关系，必须同时更新本文件，不能只改代码不改文档。
- 不要把这里写成通用 Neovim 教程；只记录当前仓库里真实存在的结构、约束和工作流。
- 优先做最小改动，保持现有模块边界与懒加载方式，不要无故把独立模块内联回 `init.lua`。

## 入口与加载顺序
- 主入口是 `vim/init.lua`。
- 启动时先启用 `vim.loader`，再确保 `lazy.nvim` 位于运行时路径中。
- 核心模块按顺序加载：
  - `lu5je0.options`
  - `lu5je0.mappings`
  - `lu5je0.plugins`
  - `lu5je0.ext-loader`
  - `lu5je0.commands`
  - `lu5je0.autocmds`
  - `lu5je0.filetype`
- 每个核心模块都通过 `pcall(require, ...)` 加载；如果某模块报错，Neovim 会继续启动并通过 `vim.notify` 报错。
- `plugin/matchparen.vim` 会在延迟回调中手动加载，因为内建 `matchparen` 已从默认运行时插件列表里禁用。

## 目录职责
- `lua/lu5je0/options.lua`: 基础选项。
- `lua/lu5je0/mappings.lua`: 全局按键。
- `lua/lu5je0/plugins.lua`: `lazy.nvim` 插件声明、补丁声明、插件级装配入口。
- `lua/lu5je0/ext-loader.lua`: 仓库自定义懒加载器，负责按 `keys`、`cmd`、`event` 延迟加载本地扩展。
- `lua/lu5je0/ext/`: 第三方插件配置适配层。通常一个插件一个文件。
- `lua/lu5je0/core/`: 可复用核心能力，供多个扩展或功能模块共享。
  - `core/buffer-modified.lua`: 'modified' 变化的兼容注册层，见下方「临时兼容」一节。
- `lua/lu5je0/misc/`: 独立功能模块与自定义工具，例如 IME、clipboard、timestamp、translator、json-helper。
- `lua/lu5je0/lang/`: 轻量通用工具函数。
- `ftplugin/`, `syntax/`, `indent/`: 文件类型定制。
- `lsp/`: 独立语言服务器配置文件。
- `patches/`: 对上游插件的补丁文件，和 `plugins.lua` 中的 `patches = { ... }` 声明联动。
- `tests/`: 当前仓库内的自动化测试。现有入口覆盖 `cron-parser`、`line-log`、`project-log`、`sidebar` 与 `multicursor`，并按功能子目录组织。
- `lib/` 下的 native 依赖优先按平台子目录组织；如果调整其落点，需要同时检查 Neovim 配置、外部消费脚本和构建同步逻辑。

## Multicursor (`ext/multicursor.lua`)

Neovim 0.13 起 multicursor 是内建能力（`:help multicursor`），不再需要 `mg979/vim-visual-multi`。
`lua/lu5je0/ext/multicursor.lua` 只做按键适配，把原生键位调成接近 vim-visual-multi 的 ctrl-n 用法。

- 能力探测用 `type(vim.api.nvim_mcursor) == 'function'`，**不要**用 `has('nvim-0.13')`：
  该 API 是 0.13 才加的 `FUNC_API_SINCE(15)`，探测 API 比探测版本号更准，也能覆盖 nightly。
- 0.12 上模块整体 no-op（但仍导出空的 `setup()`，因为 `ext-config.lua` 会无条件调用）。
  同一套 `<C-n>`/`<M-n>` 由 `vim-visual-multi` 提供，见下。
- 键位：`<C-n>` 逐个加下一个匹配（进入 extend 模式=每个 cursor 各持一个词的选区）、
  `<M-n>` 下方同列加 cursor，两者都开 follow-mode（`q=`）；原生 `Q`/`[count]Q`/`gQ`/`]C`/`g<C-A>` 保留默认，`Q` 自己会关 follow。
- 退出用 `<C-l>`（见下），**不用** `<Esc>`：仓库里 `<C-l>` 是 `<C-w>l`（`keymaps.lua`），
  所以只在有 cursor 时挂一个 buffer-local 覆盖它，没 cursor 时完全不碰。
- `\A`：一次选中当前词/选区的**所有**匹配（对齐 vim-visual-multi 的 Select All，它的 `VM_leader` 是 `\`）。
  primary 取离原光标最近的匹配；不会为 primary 自己再加 anchor（`nvim_mcursor` 不去重）；
  连按幂等（已存在的位置不会重复加）。
- `<C-p>` / `<C-x>`：对齐 vim-visual-multi 的 Remove Region / Skip Region，
  仅在有 cursor 时 buffer-local 挂载，退出时还原原映射。
  - `<C-p>`（Remove）：删掉当前 region（primary 所在处），primary 换成另一个 cursor。
  - `<C-x>`（Skip）：丢弃当前位置、primary 前进到下一个匹配；**anchor 不变**（总数不变）；
    找不到就提示且不动（不环绕）。
  - **`<C-n>`/`\A` 必须把 pattern 写进 `@/`（`remember_pattern()`）**：它们内部用
    `vim.fn.searchpos()`，它**不更新**搜索寄存器；而 `<C-x>` 靠 `@/` 找下一个匹配。
    不写的话 `@/` 为空或是陈旧值时，`<C-x>` 会误报 `no more matches`（用户报告过），
    且 `<C-n>` 之后 `1Q` 全选也用不了。只 `setreg('/')` + `histadd`，**不要**顺手开 `hlsearch`。
  - `<Esc>` 退出 extend 后 anchor 的显示列会落在词尾（如 `1:0` -> `1:2`），
    这是上游 `mc_vsel_refresh()` 的 extmark gravity 行为，**不影响编辑位置**（实测 `x` 仍删行首），
    不要去"修"它。
  - 上游只有「加 cursor」的 API，删除只能删 anchor extmark；primary 本身不是 extmark，
    所以 Remove 的实现是「删一个 anchor + 把 primary 搬过去」。删 anchor 会清掉所有选区末端
    （`nvim.multicursor.cursor`），所以删完必须 `1q=` + `viw` 重建 extend。

### `<C-l>` 是 buffer-local 且懒挂载的（取代之前的 `<Esc>` 方案）

`<C-l>` **不是**永久全局映射，只在「本 buffer 有 cursor」时挂一个 buffer-local 映射，
会话结束立刻 `keymap.del`，并**还原**可能被覆盖的原 buffer-local `<C-l>`（例如
`ext/sidebar/actions/diff_preview.lua` 自己装了 `<C-l>`）。

- 因而：没 cursor 时 `<C-l>` 就是原来的（全局 `<C-w>l` 或 diff_preview 的映射），完全不经过 Lua。
- `n` + `x` 两个模式都挂：`<C-n>`/`<M-n>` 结尾停在 extend（visual）模式，需要先在 x 模式能命中。
- 挂钩点：包裹上游 `vim._core.mcursor.enable()`（`src/nvim/mcursor.c` 的 `mc_lua_enable`，
  核心在会话开始/结束会调它），在回调里 `vim.schedule(sync_cl_map)`，再用 `mc.active()` 重判。
  另外 `BufEnter`/`BufDelete`/`BufWipeout` 兜底。
- 坑 1：`nvim_buf_get_keymap()` 返回的 `lhs` 是规范化的 `<C-L>`（大写 L），
  与 `'<C-l>'` 比对前必须 `:lower()`，否则 capture 永远失败、还原丢失。
- 坑 2：`cl_action` 要**先** `unmount_cl()`（含还原）**再** `clear()`。因为 `clear()` 会触发
  上游 `enable(false)` → scheduled `sync_cl_map` → `unmount_cl`，那时 `cl_saved` 已被清空，还原就丢了。
- 测试注意：清 namespace 是异步触发卸载的，`reset()` 里要 `vim.wait(60, ...)` 等一拍，
  否则上一条用例遗留的 buffer-local `<C-l>` 会污染下一条。

### git 操作保护（configurable）

multicursor 会话中，**会改 buffer 的 reset 类 git 操作会被拦截**（不执行 + 提示），
因为整行 `nvim_buf_set_lines()` 会把 multicursor 的 anchor extmark（right_gravity）
推到下一行，导致 cursor 合并/错位（最小复现见模块内注释）。

- 默认名单 `guarded_keys = { '<leader>gu', '<leader>gC' }`：
  - `reset_hunk`（gitsigns / diff-base）与 `reset_buffer`（diff-base）会 `set_lines`；
  - gitsigns 里 `set_lines` 只出现在 `reset_hunk` 一处（`actions.lua:361`）；
  - `stage_*` / `unstage_*` 只写 git index、不动 buffer，**不拦**。
- 配置：`require('lu5je0.ext.multicursor').setup { guard = bool, guarded_keys = {...}, guard_message = string|fun() }`，
  在 `ext-config.lua` 的 multicursor 条目里传入。`guard=false` 则完全不接管。
- 实现与 `<C-l>` 同一套机制：会话中把对应键换成 buffer-local 拦截映射，退出时**还原**原映射。

**坑：`nvim_buf_get_keymap()` 返回的 lhs 会把 `<leader>` 展开**（`<leader>gu` → `,gu`）。
capture / restore 都必须先 `expand_leader()`，否则永远匹配不到（gitsigns/diff-base 的 `gu`
都是用 `<leader>` 定义的），表现为「退出后原映射丢失」。

### 五个实现上的坑（改动前务必看）

1. **`busy` 重入锁是必须的**。上一轮开了 follow-mode；本次在 mapping 里移光标后，上游
   `atom_clock_edge` 会命中 `follow && map_moved && !Visual.active` 而触发
   `atom_lhs_replay_queue()`，把整个 `<C-n>` 配方在每个已有 cursor 上重放一次，
   表现为「按 3 次变成 5 个 cursor」——实测 nc 序列 `1,2,5,9`。级联重放会再次递归进入
   mapping，`busy` 直接挡掉。锁必须在回调结尾复位，**包括「无下一个匹配」的早退分支**，
   且 `<C-n>`/`<M-n>` 共用同一个 `busy`。
2. **`<C-n>` 必须同步执行（不能包 `vim.schedule`）**。早期版本把函数体包进 `vim.schedule`，
   那就是「光标闪一下」的根源：移光标延后一拍 → 先重绘一次（光标还在旧位置），再重绘到
   新位置。有了第 1 点的 `busy` 锁，同步执行不会产生级联。
   `<C-n>` 结尾停在 visual 模式，`!Visual.active` 不成立，所以内联是安全的。
3. **`<M-n>` 必须保留 `vim.schedule`**（与 `<C-n>` 相反）。它结尾停在 normal 模式：
   mapping 内同步移光标 + 开 follow 会命中同一条 `follow && map_moved && !Visual.active`，
   且在 mapping 返回后才重放（那时 `busy` 已复位），导致丢 cursor / 数量错乱。
   整块延后一拍就不会落进当次 CmdAtom。
4. **`x`-mode mapping 里 `vim.fn.visualmode()` 返回空串**（选区已结束），必须从 `vim.fn.mode()`
   推导 `v`/`V`/`<C-v>` 类型；且退出 visual 后窗口光标停在「活跃端」，要显式算选区起点，
   否则留下来的 cursor 会落在词中间。
5. **不要在 mapping 回调里 `vim.keymap.del` 掉正在执行的那个映射**。实测（`<C-l>` 早期实现）
   会让回调**立即中止**，后面的语句不再执行（表现为「`<C-l>` 清不掉 cursor」）。
   所以 `cl_action` 不直接删映射，而是把要还原的状态寄存到 `pending_unmount`，
   由 `clear()` 触发的 `enable(false)` → `scheduled sync_cl_map` 去真正 del/restore。
   推论：`unmount_*` 都接受可选的 `(buf, saved)` 覆盖参数，以便 `sync_cl_map` 消费寄存状态。

### 与 vim-visual-multi 的切换

`plugins.lua` 里给 `mg979/vim-visual-multi` 加了 `enabled = function() return type(vim.api.nvim_mcursor) ~= 'function' end`，
即 0.12 用插件、0.13 用原生，避免两套键位/语义打架。
**删除条件**：仓库不再支持 0.12（或 `nvim-cmp` 等旧插件一并移除）时，可删掉 vim-visual-multi、
`ext/vim-visual-multi.lua` 及其 `keys` 声明；`ext/multicursor.lua` 的能力探测也可简化掉。

## Tabline (自定义实现)

`lua/lu5je0/ext/tabline/` 是替代 `akinsho/bufferline.nvim` 的纯 Lua tabline 实现，通过 `vim.o.tabline` 渲染。

### 目录结构

```
ext/tabline/
├── init.lua        -- 入口：setup()，导出 buffer_name_map
├── config.lua      -- 选项、offsets、keymap 注册（setup_keymaps）
├── highlights.lua  -- 动态高亮（从 colorscheme 推导颜色）
├── state.lua       -- 模块级缓存：buffer_name_map、ordinal_to_buf、pick 状态
├── naming.lua      -- Untitled-N gap-fill 命名分配
├── render.lua      -- 纯 tabline 字符串构建 + truncation + 鼠标点击 + tab 页指示器
├── offsets.lua     -- 检测左侧 sidebar 窗口生成 offset 填充块
├── actions.lua     -- cycle / go_to_ordinal / close_left / close_right / close_others
├── pick.lua        -- 字母分配 + getcharstr 选择
├── commands.lua    -- 用户命令注册
└── autocmds.lua    -- 单 augroup 'tabline'，事件触发 refresh
```

`ext/bufferline.lua` 是兼容 shim，返回 `require('lu5je0.ext.tabline.init')` 并调用 `setup()`。

### 架构设计

- **颜色动态推导**：`highlights.apply()` 从 `Normal`、`Comment`、`String`、`TabLineSel`、`DiagnosticError`、`WinSeparator` 等 hl group 读取颜色，经 shade/tint 计算后设置所有 `BufferLine*` 高亮组。`ColorScheme` 事件时自动重新应用。
- **Devicon 组合高亮**：`render.lua` 为每个 file icon 创建 `BufferLineIcon_<iconHl>_<tabHl>` 组合组（icon fg + tab bg），`ColorScheme` 时清除缓存。
- **Truncation**：buffer tab 放不下时，从两侧平衡裁剪，当前 buffer 始终保留。显示 ` N  ` / ` N  ` 标记。
- **Tab 页指示器**：多 tabpage 时右对齐显示 tab 编号 + 关闭按钮。
- **Offset**：扫描当前 tabpage 左侧窗口，按 filetype 匹配 `config.offsets` 表，手动空格填充实现居中/左/右对齐，末尾追加 `█` separator。宽度包含 window separator 的 1 列。
- **懒加载**：通过 `ext-config.lua` 的 `lazy_load` 注册，`UIEnter` 事件触发。setup 中 `commands` 和 `config.setup_keymaps` 延迟到 `vim.schedule`。

### 兼容接口

- `require('lu5je0.ext.tabline').buffer_name_map`：被 `sidebar/sources/buffers.lua` 读取以显示 Untitled-N 名称。
- `require('lu5je0.core.buffers').valid_buffers()`：共享 buffer 列表函数（`buflisted` + `is_valid`），被 bufferline、sidebar、time-machine 共用。

### 按键映射

| 按键 | 功能 |
|------|------|
| `<leader>0` | Pick 模式（字母跳转） |
| `<leader>1..9` | 跳转到第 N 个 buffer |
| `<leader>to` | 关闭其他所有 buffer |
| `<leader>th` | 关闭左侧 buffer |
| `<leader>tl` | 关闭右侧 buffer |
| `<left>` | 切换到上一个 buffer |
| `<right>` | 切换到下一个 buffer |

### Nerd Font 图标

- `render.lua` 包含 Nerd Font 图标字符（truncation arrows U+F0A8/U+F0A9）。
- **不要用 Edit 工具直接编辑这些图标行**，多字节 UTF-8 匹配容易失败；需要时用 python/sed 写入。

### 维护注意

- 新增/修改高亮组时，在 `highlights.apply()` 的 `groups` 表内操作，不要散落到其他文件。
- 改动 buffer 列表逻辑时，确认 `core/buffers.lua` 的消费方（sidebar、time-machine）不受影响。
- 改动 offset 逻辑时，确认 sidebar 的 foldcolumn/signcolumn 宽度是否影响对齐。

## 改动落点规则
- 改基础编辑行为、选项默认值，优先改 `options.lua`、`mappings.lua`、`autocmds.lua`、`commands.lua`。
- 改第三方插件行为，优先改 `plugins.lua` 中对应 spec，或 `ext/` 下对应适配文件；不要把插件细节散落到多个无关模块。
- 新增仓库自定义功能，优先放到 `misc/` 或 `core/`，再在 `ext-loader.lua` 或其他明确入口里接入。
- 新增按键或命令时，先判断是否应该懒加载；已有模式是由 `ext-loader.lua` 代理首次触发并回放按键/命令。
- 修改 LSP 行为时，同时检查 `lsp/` 与 `core/lsp.lua` 是否都有联动。
- 修改文件树、补全、输入法、剪贴板等平台相关功能时，确认 macOS / WSL / Windows 路径或二进制名是否受影响。

## 插件与补丁约定
- 插件列表集中在 `lua/lu5je0/plugins.lua`。
- 当前配置依赖 `lazy.nvim`，并使用：
  - `event`
  - `keys`
  - `cmd`
  - `dependencies`
  - `patches`
- 如果插件行为依赖仓库内补丁，必须同时维护 `patches/*.diff` 与 `plugins.lua` 中对应的 `patches` 声明。
- 改插件版本、插件源、锁定策略时，检查是否需要同步更新 `lazy-lock.json`。
- 仅在确有必要时调整 `disabled_plugins` 列表；这会直接影响启动时的运行时插件集合。

## TUI Bridge 与平台联动
- `lua/lu5je0/misc/tui-bridge/`、`lua/lu5je0/misc/ime/`、`lua/lu5je0/misc/clipboard/` 含平台相关逻辑。
- `lua/lu5je0/misc/clipboard/init.lua` 按平台选择后端：SSH 走 OSC52；macOS / WSL / Linux 桌面均走 `clipboard/tui-bridge.lua`（native `tui-bridge` 进程桥接）。
  - Linux 的 native 实现在 `submodule/tui-bridge/linux/clipboard-bridge.c`：libwayland-client + data-control 协议（优先 `ext_data_control_v1`，回退 `zwlr_data_control_unstable_v1`），由常驻 `-i` 进程持有 selection；`clipboard.input` / `clipboard.output` 都带 `selection` 参数（`regular`/`primary`），一次只动一个 selection。
  - `clipboard/tui-bridge.lua` 里 `+` 与 `*` 语义分离，不要再把两者指向同一个函数：`vim.o.clipboard = 'unnamedplus'`，`+` 走 CLIPBOARD 且复用 `active_entry` 缓存（缓存只在 FocusGained/启动时同步）；`*` 是 primary selection，每次实时读写、不进缓存——鼠标在别的应用里划选不产生任何能让 Neovim 同步的事件，走缓存必然粘出旧内容。同理 `core/clipboard.lua` 的 `M.set` 只写 `+`，写 `*` 会覆盖用户刚划选的内容。
  - 旧的纯 Lua 实现 `wayland.lua`（LuaJIT FFI 手写 Wayland wire 协议）保留在仓库但已不接入，不作为 fallback。注意纯 X11/XWayland 桥接方案在 KWin 上无法粘贴 Wayland 内容(KWin 仅在 X11 窗口获焦时才同步)，故未采用。
- `bin/macos-arm64/tui-bridge`、`bin/windows-x86_64/tui-bridge` 与 `bin/linux-x86_64/tui-bridge`（仓库顶层 `bin/`，非 `vim/lib`）来自 `submodule/tui-bridge` 构建产物；平台由目录区分，文件名统一为连字符 `tui-bridge`。`lua/lu5je0/misc/tui-bridge/tui-bridge.lua` 直接解析 `~/.dotfiles/bin/<平台-架构>/tui-bridge`，不再走 `core.native`。不要在 Neovim 侧文档中把它们描述成普通 Lua 模块。
- `lua/lu5je0/core/native.lua` 负责解析 `vim/lib/` 下剩余的 native 资源（如 `liblibclipboard.dylib`）；新增落在 `vim/lib/` 的动态库时优先复用这个入口，不要硬编码 `stdpath('config') .. '/lib/...'`。注意 `tui-bridge` 已迁出 `vim/lib`，不再经此解析。
- 如果任务改动了桥接协议、IME 行为、剪贴板桥接或二进制同步流程，必须同步检查 `submodule/tui-bridge/AGENTS.md`。
- macOS、Windows/WSL 与 Linux 桌面共用同一个 IME 后端 `lua/lu5je0/misc/ime/tui-bridge/backend.lua`（由 `misc/ime/init.lua` 的 `select_backend_module` 选中）；平台差异下沉到 native `tui-bridge`，Lua 侧只按归一化的 `ime_changed.state`（`ascii`/`ime`）判断，keeper 不再按平台分叉。旧后端 `lua/lu5je0/misc/ime/mac/backend.lua`(XkbSwitchLib FFI) 与 `lua/lu5je0/misc/ime/linux/backend.lua`(busctl 轮询 fcitx5 rime) 保留但已不接入。
- 会临时切换内部窗口的输入 UI 通过 `require('lu5je0.misc.ime').set_typing_context(name, active)` 声明输入上下文；例如 Telescope 在 prompt 生命周期内保持该上下文，避免 preview 刷新产生的短暂 Normal 模式关闭 IME。
- kitty 下优先走 OSC 后端 `lua/lu5je0/misc/ime/osc/backend.lua`（kitty 原生处理 `SetUserVar=tui-bridge`，按窗口屏蔽自身 IME）。识别由 `select_backend_module` 前的 `is_kitty()` 负责：tmux 内 `TERM` 是 tmux 自己的 terminfo，改问 `tmux display-message -p '#{client_termname}'`（带 `-t $TMUX_PANE`），只在 tmux 里 fork 一次。
- OSC 后端在 tmux 内会把转义序列包进 `\ePtmux;…\e\\`（内层 ESC 加倍），否则 tmux 直接吞掉 OSC 1337；依赖 `tmux/tmux.conf` 的 `allow-passthrough on`。`zsh/vi-im-switch.zsh` 用同一套包装。

## 测试与验证
- 最小启动验证：
  - `cd vim && nvim --headless '+qa'`
- 当前自动化测试入口：
  - `cd vim && ./tests/run-tests.sh`
- `tests/run-tests.sh` 通过 `luajit` 运行 `tests/cron/spec.lua`（要求设置 `DOTFILES_ROOT`），并通过 `nvim --headless -u NONE -l` 运行 `tests/line-log/spec.lua`、`tests/project-log/spec.lua`、`tests/sidebar/state_spec.lua`、`tests/sidebar/spec.lua`、`tests/sidebar/interactive_spec.lua`、`tests/sidebar/diff_preview_spec.lua`、`tests/sidebar/parser_spec.lua`、`tests/sidebar/git_changes_spec.lua`、`tests/sidebar/git_ops_spec.lua`、`tests/winbar/drag_spec.lua`、`tests/multicursor/spec.lua`。
- `tests/multicursor/spec.lua` 只在 0.13+（当前 nvim 的 `vim.api.nvim_mcursor` 存在）真正执行，老版本输出 `SKIP` 并退出 0。
  它起一个 `--embed` 子 Neovim、用 `nvim_input()` 发真实按键：multicursor 的 CmdAtom / follow-mode
  只在 typed 路径上被捕获，`vim.api.nvim_feedkeys(..., 'x')` 在脚本里行为不可靠。
  要在 0.12 下验证这部分，得用 0.13+ 的 nvim 跑整套测试；`NVIM_TEST_BIN` 只用于在外层已是 0.13 时指定另一个 0.13 二进制
  （0.12 的 `rpcrequest` 对着 0.13 子进程会挂死，不能用来“升级”外层）。
- `tests/winbar/drag_spec.lua` 是唯一会起子 Neovim 并 attach UI 发真实鼠标事件的测试（winbar tab 拖动），坑点见 `lua/lu5je0/ext/winbar/agents.md` 的「测试」一节。
- 如果你新增了独立 Lua 功能且具备稳定输入输出，优先补到 `tests/`，不要只依赖手动打开 Neovim 验证。
- 如果改动只覆盖某个懒加载模块，至少补一次对应命令、按键或事件的首次加载路径验证。

## 提交流程建议
- 改完入口或模块后，先跑 `nvim --headless '+qa'`，尽可能不在沙箱内运行，确认没有直接语法错误或 require 失败。
- 改插件补丁时，确认补丁文件、插件声明、运行时行为三者一致。
- 改平台相关能力时，在提交说明里明确受影响平台与未验证平台。

## 临时兼容

### BufModifiedSet / OptionSet modified（`core/buffer-modified.lua`）

背景：0.12 与 0.13 的 'modified' 事件模型不同，单用任何一个都会漏。

| 路径 | 0.12 触发 | 0.13 触发 |
|------|-----------|-----------|
| 自然编辑 / undo / `dd` / `x` | `BufModifiedSet` | `OptionSet modified` |
| `:set [no]modified` | `OptionSet modified` | `OptionSet modified` |

- 0.12（`release-0.12`）：自然编辑只置 `b_changed_invalid = true`，由主循环（`normal.c` / `edit.c`）派发 `BufModifiedSet`；`OptionSet modified` 只在显式 `set` 时经 `apply_optionset_autocmd()` 触发。
- 0.13：`BufModifiedSet` 已移除（`news.txt` / `deprecated.txt`，PR #35610）。`changed_internal()` / `unchanged()` 直接调 `aucmd_defer_modified()`，`OptionSet modified` 覆盖自然编辑。

因此 `core/buffer-modified.lua` 用 `vim.fn.exists('##BufModifiedSet')` 探测能力，两个都注册。0.12 上两条路径互斥（各触发一次），不会重复触发。

**删除条件：当运行版本已经是 0.13 正式版（`vim.fn.has('nvim-0.13') == 1`，即 `BufModifiedSet` 已不存在）时，删除该文件**，并把 `winbar/autocmds.lua` 与 `sidebar/sources/buffers.lua` 的 `require('lu5je0.core.buffer-modified').register(group, cb)` 直接换成：

```lua
vim.api.nvim_create_autocmd('OptionSet', {
  group = group,
  pattern = 'modified',
  callback = cb,
})
```

注意：`OptionSet` 必须单独注册（需要 `pattern`，无法并入 `BufAdd/BufEnter/...` 那组事件表），且 `'modified'` 触发时是 deferred 派发。

消费方（两处）：
- `lua/lu5je0/ext/winbar/autocmds.lua`：刷新 winbar 的 modified 标记（●）。
- `lua/lu5je0/ext/sidebar/sources/buffers.lua`：刷新 Buffers source 的 `●`。

两处都**不能删掉这个事件**：`:set modified` 不走 Neovim 的 winbar 重画路径，且 winbar/sidebar 渲染的是所有 listed buffer，而内置重画只覆盖显示该 buffer 的窗口。

### multicursor：0.13 原生 vs 0.12 vim-visual-multi

0.13 起 `Q` 变成「加 multicursor」，而仓库里 `keymaps.lua` 原本把 `Q` 映射成回放录制寄存器。
该行现已注释掉（注释后在两个版本上都是对的：0.12 的 `Q` 默认本来就回放寄存器）。

切换条件统一用能力探测 `type(vim.api.nvim_mcursor) == 'function'`（两个位置）：

| 位置 | 0.12 | 0.13+ |
|------|------|-------|
| `ext-config.lua` 的 `multicursor` 条目 | `ext/multicursor.lua` 内部 no-op | 注册 `<C-n>`/`<M-n>`/`<Esc>` |
| `plugins.lua` 的 `mg979/vim-visual-multi` | `enabled` → 加载插件 | `enabled` → 禁用 |

细节见本文件「Multicursor (`ext/multicursor.lua`)」一节。测试：`tests/multicursor/spec.lua`（老版本自动 SKIP）。

## 已知事实
- 仓库根 README 将该目录视为 `neovim` 配置的一部分。
- 当前仓库在 `vim/` 目录下使用 `stylua.toml`，说明 Lua 格式化约定已本地化到该目录。
- 当前没有覆盖整个配置的完整端到端测试；很多能力仍依赖启动验证和定向手工验证。
