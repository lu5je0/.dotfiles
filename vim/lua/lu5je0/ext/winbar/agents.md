# Winbar 工作指引

## 适用范围
- `vim/lua/lu5je0/ext/winbar/` 下的窗口 buffer 标签实现。
- 通过 `vim.wo[win].winbar` 渲染，每个窗口独立跟踪 buffer 列表；`showtabline = 0`。

## 目录结构

```
ext/winbar/
├── init.lua        -- 入口：setup()，导出 buffer_name_map
├── config.lua      -- 选项、offsets 表、keymap 注册（setup_keymaps 延迟到 vim.schedule）
├── highlights.lua  -- 动态颜色推导（derive_colors → apply）
├── state.lua       -- buffer 名称、全局/per-window 顺序、pick 与拖动状态
├── naming.lua      -- Untitled-N gap-fill 命名分配器
├── render.lua      -- winbar 字符串、截断、鼠标点击区域与动画布局
├── offsets.lua     -- 检测左侧 sidebar 窗口，生成 offset 填充块
├── actions.lua     -- cycle / go_to_ordinal / close_left / close_right / close_others
├── drag.lua        -- 拖动重排：LeftDrag/LeftRelease expr 映射 + 列命中 + move
├── canvas.lua      -- 单元格画布：解析 segment markup → cells，可重叠/裁剪落位再序列化
├── anim.lua        -- 拖动跟随 + 换序动画：被拖 tab 跟随鼠标浮动，其余 tab uv 定时器缓动让位
├── pick.lua        -- 字母分配 + getcharstr 选择模式
├── commands.lua    -- 用户命令注册（延迟到 vim.schedule）
└── autocmds.lua    -- 单 augroup 'winbar'，事件触发 debounced refresh
```

`ext/bufferline.lua` 是兼容 shim：`require + setup()` + 返回模块。

## 架构约定

- **颜色动态推导**：`highlights.apply()` 从当前 colorscheme 的 `Normal`、`Comment`、`String`、`TabLineSel`、`DiagnosticError`、`WinSeparator` 读取颜色，经 `shade()` 计算后设置所有 `BufferLine*` 高亮组。`ColorScheme` autocmd 重新应用。
- **Devicon 组合高亮**：`render.lua` 为每个文件 icon 创建 `BufferLineIcon_<iconHl>_<tabHl>` 组（icon fg + tab bg）。`ColorScheme` 时通过 `clear_icon_hl_cache()` 清除缓存。
- **Truncation**：放不下时从两侧平衡裁剪，当前 buffer 始终保留。左/右显示 ` N <arrow> ` 标记。
- **Tab 页指示器**：多 tabpage 时右对齐显示可点击的 tab 编号。
- **Offset**：扫描 tabpage 左侧窗口，按 filetype 匹配 `config.offsets`，手动空格填充居中，末尾追加 `█` separator。宽度 = `win_width + 1`（含 window separator 列）。
- **装配**：`ext-config.lua` 通过 `ext_load` 加载；setup 同步执行 `highlights.apply`、注册 autocmd 并设置 winbar；`commands` 和 `config.setup_keymaps` 延迟到 `vim.schedule`。
- **拖动重排**（Chrome 风格）：`render.lua` 每次渲染把可见 tab 的列区间写入 `state.tab_regions[win]`（`wincol` 1-based，含 truncation 标记与 partial 宽度）。左键点击经 click region `_click` 记录 `state.drag = {buf, win}`。`drag.lua` 用 expr 映射 `<LeftDrag>`/`<LeftRelease>`：有会话时消费事件并按 `getmousepos().wincol` 命中目标 ordinal，`move` 重排后 `redrawstatus!`；无会话时返回原键透传，保留鼠标划选。顺序落点：单窗口单 tabpage 写 `state.buf_order`（`util.ordered_valid` 持久化，`get_buf_list` 复用，故键盘 `cycle`/`go_to_ordinal` 也遵循），否则写 `state.win_bufs[win]`。
  - **拖动阶段**：`<LeftDrag>` 实时（`on_drag`）：鼠标在起始窗口内则重排；一旦移入**另一个 normal 窗口**即实时跨窗口移动，目标窗口显示该 buf 并 `set_current_win` 过去。若被移走的是源窗口**最后一个** tab（且非 tabpage 唯一窗口），不立即关窗，而是标记 `state.pending_close_win`：该窗口 `build_winbar` 短路返回空 tab 栏（保留窗口本身），直到 `<LeftRelease>`（`finish_drag`）才 `close_pending` 真正关掉。所有 buffer/窗口变更都 `vim.schedule` 出 expr 上下文（避免 textlock）；关窗前清空 `state.win_bufs[src]` 以免 `WinClosed` autocmd 把 buf 重分配回来。
  - **快照式重算**：`drag.begin` 保存 `win_bufs` 与 `buf_order`，每个拖动事件通过 `apply(snapshot, origin_win, buf, target_win, ordinal)` 从快照重算布局。移除只作用于原窗口，目标窗口已有该 buffer 时只重定位；拖回原窗口恢复初始布局并清空 `pending_close_win`，避免多窗口共享 buffer 时累计修改导致误删。
  - **拖动跟随 + 换序动画**：被拖 tab 的浮动列 = `mouse.wincol - grab_offset`（`grab_offset` 在 `_click`/`begin` 时按 `mouse - region.from` 记下，避免起拖跳变），逐帧直接跟随鼠标、不缓动；其余 tab 用 `vim.uv` 定时器（16ms、指数缓动）让位到各自槽位（`anim.follow`）。**换序阈值 = 被拖 tab 中心落进另一个 tab 的列区间**（等宽时等价于 >50% 重叠），由 `drag.follow_target` 按布局区间判定，不用固定公式。松手（`anim.release`）后被拖 tab 从浮动位缓动进目标槽再落定。渲染：`canvas.parse` 把 markup 解析成逐格 cell，`canvas.paint` 按浮动/缓动列合成（被拖 tab 最后画、压在最上），`canvas.serialize` 还原 winbar 字符串并重建点击区；`render.winbar` 动画期间返回 `anim.frame(win)`（外层包 pcall 兜底），否则走静态 `build_winbar`。
  - **动画布局**：复用 `render.layout(win)` 中包含截断的静态布局；`build_winbar` 计算并缓存，`render.forget` 清理。不可见标签不绘制，截断标记使用固定列；可见范围变化时，新增可见标签直接吸附槽位，避免从屏幕外缓动。
  - **拖动原点与宿主**：`drag.win` 始终表示快照原窗口，`drag.host` 表示标签当前所在窗口。跨窗口时更新 host，并对旧 host 调用 `anim.reflow` 合拢空位；动画不改变快照原点。
  - `WinClosed` 时清理 `anim.clear(win)` / `render.forget(win)` / `state.tab_regions[win]`，因为窗口 id 会被复用。

## Nerd Font 图标

- `render.lua` 包含 Nerd Font 图标字符（truncation arrows U+F0A8 / U+F0A9）。
- 修改图标后检查 diff，确认 UTF-8 字符完整。

## 兼容接口

- `ext/bufferline.lua` 导出 winbar 的 `buffer_name_map`，供 `sidebar/sources/buffers.lua` 显示 Untitled-N 名称；修改结构时检查消费方。
- `require('lu5je0.core.buffers').valid_buffers()`：共享 buffer 列表（buflisted + is_valid），被 winbar、sidebar、time-machine 共用。

## 按键映射

| 按键 | 功能 |
|------|------|
| `<leader>0` | Pick 模式（字母跳转） |
| `<leader>1..9` | 跳转到第 N 个 buffer |
| `<leader>to` | 关闭其他所有 buffer（走全局列表，见「维护注意」） |
| `<leader>th` | 关闭左侧 buffer |
| `<leader>tl` | 关闭右侧 buffer |
| `<left>` | 切换到上一个 buffer |
| `<right>` | 切换到下一个 buffer |
| 鼠标左键拖动 tab | 重排 buffer 顺序（松开落位） |

## 维护注意

- 新增/修改高亮组：在 `highlights.apply()` 的 `groups` 表内操作，不要散落到其他文件。
- 改动 buffer 列表逻辑：确认 `core/buffers.lua` 的消费方（sidebar、time-machine）不受影响。
- 改动 offset 逻辑：确认 sidebar 的 foldcolumn/signcolumn 宽度是否影响对齐。
- 改动 truncation 或 tab 指示器宽度计算时，两处必须同步（`tab_section_w` 估算 + 实际渲染）。
- **关闭范围**：`<leader>to` 从 `core/buffers.valid_buffers()` 关闭全局其他 buffer；`<leader>th` / `<leader>tl` 按
  `util.get_buf_list()` 关闭当前窗口列表中的左侧 / 右侧 buffer。拖动、`cycle`、`go_to_ordinal` 使用窗口列表。
- **安全关闭**：`bdelete_safe` 跳过 modified 或正在其他窗口显示的 buffer，避免丢失编辑或关闭其他窗口。
  `displayed_elsewhere` 检查所有 tabpage 的实际窗口，不以 `state.win_bufs` 的记录判断可见性。
  删除当前窗口的 buffer 前先切换到相邻 buffer；跳过时通过 `vim.notify` 说明原因。
- 拖动/跨窗口移动后必须用 `redrawstatus!`（带 `!`）：不带 `!` 只重画当前窗口的 winbar，源窗口会残留旧 tab，直到切回该窗口才更新。
- `modified` 标记刷新用 `require('lu5je0.core.buffer-modified').register(group, cb)`：0.12 的自然编辑走 `BufModifiedSet`，0.13 移除此事件；显式 `:set modified` 两版本都走 `OptionSet` + `pattern = 'modified'`。兼容层与删除条件见 `vim/AGENTS.md` 的「临时兼容」一节。
- 显式 `:set modified` 需要主动刷新标签；内置重画只覆盖显示该 buffer 的窗口。

## 测试

- `tests/winbar/drag_spec.lua`：拖动行为的端到端回归测试，入口在 `tests/run-tests.sh`。
- `tests/winbar/close_others_spec.lua`：`<leader>to` 语义的回归（单窗口 / 有未保存修改 / `vsplit`
  出新窗口 / 光标在侧栏 / 第二个 tabpage 五种布局，断言"全局列表 + 不删可见的 + 不带走窗口"）。
- 它用 `jobstart(..., {rpc=true})` 起一个 `nvim --embed` 子进程并 `nvim_ui_attach`，再用 `nvim_input_mouse` 发真实 press/drag/release，覆盖真正的 click region 与 `<LeftDrag>` 映射。
- 写这类测试时的三个坑：
  - `nvim_ui_attach` **不能带 `ext_linegrid`**，父进程不是真正的 grid UI，子进程会直接退出。
  - 没有 attach UI 的 headless 子进程会静默丢弃 `nvim_input_mouse`，纯 headless 复现不出鼠标行为。
  - tab 的 separator 与居中 padding **在 click region 之外**，点击坐标要从 `state.tab_regions` 的区间中点算，不能猜列号。
