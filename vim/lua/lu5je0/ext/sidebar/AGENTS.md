# Sidebar 工作指引

## 适用范围
- `vim/lua/lu5je0/ext/sidebar/` 下的自定义树形侧边栏插件，替代 nvim-tree。
- 顶部 winbar 默认依次显示 Files、Symbols、Changes；History / Buffers 是临时页签，快捷键打开后显示，关闭 Sidebar 后移除。左右键仅遍历可见页签，每次最多显示三个。

## 目录结构

```
sidebar/
├── init.lua           -- 入口：setup / toggle / focus / open_tab / locate_in_tab / _on_dir_changed
├── config.lua         -- 配置：图标、highlight、tabs、宽度；M.apply_highlights() 集中应用
├── state.lua          -- per-tab 状态（metatable 按 tabpage 隔离），new_tab_state() 是 schema 单一来源
├── git_status.lua     -- 单次异步 git status，按 tab 更新 Files/Git Changes 缓存并合并刷新请求
├── watcher.lua        -- 展开目录/Git 元数据 fs_event 与资源释放（无定时轮询）
├── window.lua         -- 窗口生命周期、guicursor
├── full_name.lua      -- 长文件名浮窗（CursorMoved/WinScrolled 触发）
├── tabs.lua           -- winbar 渲染、tab 切换
├── keymaps.lua        -- 共享 + per-tab 快捷键管理
├── autocmds.lua       -- 集中注册到 `sidebar` augroup（DirChanged / TabEnter+TabClosed / WinClosed /
│                          ColorScheme / BufWritePost+FileChangedShellPost+FocusGained / BufEnter+LspAttach /
│                          buffers source 自动刷新：BufAdd+BufDelete+BufWipeout /
│                          core.buffer-modified 注册的 'modified' 事件）
├── render.lua         -- 纯渲染引擎：tree → lines/items/highlights/virt_texts
├── view.lua           -- buffer/window 写入：flush / open_node / close_node / restore_cursor
├── source_base.lua    -- Source 基类：build / render_opts / decorate / post_flush / open / close
├── sources/
│   ├── files.lua             -- 兼容 shim → sources.files.init
│   ├── files/
│   │   ├── init.lua          -- files source 门面（render / open_node / find_file / cd_* / keymaps）
│   │   ├── tree.lua          -- 节点 / scan_dir / ensure_children / rescan / rel_to_cwd / make_filter
│   │   ├── git.lua           -- build_status_map / status_to_glyph / is_git_item
│   │   ├── live_filter.lua   -- 过滤 overlay（per-tab buf/win/closing 在 state.files._live_filter）
│   │   └── info.lua          -- show_file_info 浮窗
│   ├── git_changes.lua       -- 兼容 shim → sources.git_changes.init
│   ├── git_changes/
│   │   ├── init.lua          -- git_changes source 门面
│   │   ├── parser.lua        -- parse_git_status / files_to_tree_nodes / git_root 缓存（自失效）
│   │   └── locate.lua        -- do_locate / do_locate_first 实现
│   ├── history.lua           -- 项目历史 source：提交树、勾选、历史 diff 目标
│   ├── buffers.lua           -- Buffers source（含 setup_auto_refresh）
│   └── symbols.lua           -- LSP Symbols source
└── actions/
    ├── file_ops.lua          -- 文件操作（剪贴板挂在 state.files._clipboard）
    ├── git_ops.lua           -- Git 操作（调用 git/common/git-ops.lua）
    ├── navigation.lua        -- cwd 历史 back/forward
    ├── preview.lua           -- 预览控制器
    └── diff_preview.lua      -- diff 预览（per-tab 浮窗，5s pending 超时兜底；`sidebar_diff_mode` 控制 dual / single 布局，`d` 切换布局、`c` 切换 changes-only，Git Changes 列表与预览窗口按键一致）
```

外部共享：`ext/git/common/git-ops.lua`（sidebar 和 git-status 共用的日志/undo/git 工具）

## Nerd Font 图标

- `config.lua` 中包含 Nerd Font 图标字符（tab label、folder icon、git glyph、section arrow、symbol kind icon）。
- **不要用 Edit 工具直接编辑这些图标行**，多字节 UTF-8 匹配容易失败，请用合适的命令修改；普通字段（如 `M.highlights`）可用 Edit。

## 架构约定

- 树渲染统一走 `render.render_tree(root_children, opts)`，不在各 source 重复实现。
- buffer/窗口写入只走 `view.lua`（`flush` / `open_node` / `close_node` / `restore_cursor`）；`render.lua` 仍 re-export 兼容旧调用。
- 展开接口的 `open.keep_cursor(item)` 控制是否保留光标；History commit、Changes 分组与 stash 节点展开后留在当前行，已展开时再次按 `l` 也保持不动；普通目录沿用进入子节点的行为。
- 每个 source 通过 `source_base.lua` 的 spec 表声明 `build / render_opts / decorate / post_flush / open / close / keymaps`，不再各自手写 render/open_node/close_node 骨架。
- History 只展示已提交历史，未提交改动由 Changes 展示。History 与其他 source 一样走 `source_base` → `render_tree` → `view.flush`；`git/project-log/model.lua` 只负责异步加载和取消，Git 算法保持独立。`git_style.lua` 共用 Changes/History 的树样式；预览 source 可声明 `preview_kind` 与 `preview_item()`，由共享 preview / diff_preview 管理浮窗；条目可通过 `preview_kind = "text"`、`lines`、`title` 提供文本预览，`text_preview` 管理 per-tab 浮窗及资源释放。
- 新增 source：在 `sources/` 下新增模块，导出 `render()` 与 `keymaps()`，在 `config.tabs` 表注册即可。
- 快捷键区分共享（`keymaps.apply_shared`）和 per-tab（source `keymaps()`）。
- source 快捷键只绑定当前页，切页时移除其他页的映射；不能把非当前页按键保留成空操作，避免 Files 的 `dd` / `cd` 使 Git Changes 的 `d` / `c` 等待后续输入。 同页存在短键和长键前缀时，先注册长键、后注册短键，使短键的 `nowait` 优先匹配；单空格预览不能等待双空格超时。
- git 工具统一用 `actions/git_ops.lua` → `ext/git/common/git-ops.lua`。
- 异步回调里先捕获 `local ts = state.tab()` 或 `state.tab_for(tabpage)`，不要直接读写 `state.xxx`。render 还要捕获 tabpage，schedule 里 `nvim_get_current_tabpage() ~= captured` 就跳过。
- 跨 tab 的资源（fs_event、timer、preview 等）放进 per-tab state，不要写成模块级 singleton；持 libuv handle 的字段在 `state.cleanup_closed_tabs` 里释放。
- per-tab schema 单一来源：所有 per-tab 字段必须在 `state.lua` 的 `new_tab_state()` 中显式声明，便于一处看清完整 shape；持 libuv handle 或浮窗的字段同时在 `release_tab_resources` 中释放。
- 初始化路径统一走 `init.init_sidebar`，不在各入口函数重复。
- 所有 sidebar autocmd 都进 `sidebar` augroup（`autocmds.lua` 集中注册），在 `setup` 时 `clear = true` 以防重复。
- Buffers source 的 `modified` 标记刷新用 `require('lu5je0.core.buffer-modified').register(group, cb)`，**不要直接写事件名**：0.12 的自然编辑走 `BufModifiedSet`（0.13 已移除，见 `news.txt` / `deprecated.txt`，PR #35610），`:set modified` 两版本都走 `OptionSet` + `pattern = 'modified'`；单用任一个都会漏。兼容层与删除条件见根 `AGENTS.md` 的「临时兼容」一节。

- source 可提供 `on_enter` / `on_leave` 生命周期；切页、切 Neovim tab 和关闭窗口由共享入口释放瞬时 UI，任务资源也须在 `state` 的 tab 清理中释放。`config.tabs[].transient` 定义临时页，显示状态保存在 per-tab `visible_tabs`，不改动稳定的 source 索引。`config.tabs[].width` 可指定默认宽度，各页宽度在 `tab_widths` 中记忆；History 默认 50 列，窗口过小时限制为屏幕的 60%。

## 快捷键

- `<leader>gs` 打开/定位 Git Changes tab（`locate_in_tab('git_changes')`）；`<leader>fg` 已移除。
- 每个 tabpage **首次**按 `<leader>gs` 进入 Git Changes 时，忽略当前 buffer，光标定位到第一个变更文件（`git_changes.locate_first_file`），由 per-tab `state.git_changes._first_located` 记录；之后同 tabpage 再按仍定位当前文件（`locate_file`）。

- Git diff 的布局与 changes-only 独立保存：`d` 保留上下文偏好；`c` 在 single 模式切换完整上下文 / 改动附近 3 行，在 dual 模式展开 / 折叠未变化区域。Space 预览期间，在列表或预览窗口按 `d` / `c` 均立即使用已加载内容刷新，不重读文件；切换布局保留当前焦点所在区域。

- 普通模式 `<leader>gl` 打开 History；`h/l`、`zo/zc` 折叠/展开，目录默认展开，连续目录链合并显示，打开目录时自动展开仅有一个子目录的连续链，在出现分支、文件或空目录时停止；收起时整条合并显示的目录链一起关闭，分支以下手动折叠的子节点保持折叠；文件行 Enter 打开工作区文件；Space 在提交行预览元数据及变更文件列表，在文件行预览历史 diff，再按进入浮窗，`d` / `c` 与 Changes 共用偏好及已加载内容，光标移走关闭预览。`m` 勾选 commit（支持 Visual），`U` 清空、Enter 查看勾选的净变化；`K` 查看提交详情，`gG` 切换 Tig v2 提交关系图（按 tabpage 保存开关，复用已加载提交的图形缓存），`r` 刷新，`ga` 加载全部，`Z` 调整宽度；标题使用正常文字对比度，短 hash 为青色、展开箭头为蓝色、日期为暖色并靠右，名称按可用宽度用省略号截断并为状态保留空间，完整信息通过 `K` 查看。

## 高亮约定

- 全部 highlight 集中在 `config.highlights` 表（包括 `Sidebar*`、`GitChanges*`、`GitFileStatus*`），由 `init.setup` → `config.apply_highlights()` 应用。
- History 的箭头、hash 与标题使用互不重叠的高亮区间，禁止同优先级叠色；Tig 图形使用上游 14 色 ANSI palette 顺序和蓝色提交节点，RGB 取当前 terminal_color 或标准 ANSI 回退，由 config.apply_highlights 集中注册。
- ColorScheme 切换时 `autocmds.lua` 会重新 apply。
- Files 的折叠目录将 Git 状态汇总为单个 `●`，优先级为冲突 > 未暂存 > 未跟踪 > 已暂存；
  冲突用红色 `!`，未暂存用琥珀色、未跟踪用紫色、已暂存用蓝色。已展开目录不显示汇总，
  文件保留具体状态图标，被忽略的目录保留灰色 `◌`；目录汇总单独判断工作区状态，
  同一文件同时有已暂存与未暂存修改时按未暂存汇总。

## 性能规则

- **render 路径禁止同步外部命令**。git 数据通过异步预加载，render 只读缓存。
- **改动涉及 render、CursorMoved、高频 autocmd 时，必须提前告知用户性能影响。**
- 所有 Git 状态触发统一调用 `git_status.lua`，由它执行一次 `git status` 并分发给 Files 与 Git Changes；不要在 source 或 autocmd 中另起查询。
- Git 查询使用 `--no-optional-locks` 避免自身写 index 触发监听回路；每个 tabpage 最多一个在途查询，查询期间的刷新请求合并为后续补查，不按时间窗口丢弃事件。
- `watcher.lua` 监听已展开目录与实际 gitdir（支持 worktree、无 index 的新仓库），只做事件防抖，不做定时轮询。刷新只扫描缓存树的展开目录，目录结构和 Git 输出均未变化时不重画。
- 打开 sidebar、切 source、返回 tabpage、FocusGained 和文件保存/重载时补刷；FocusGained 同时同步监听，覆盖离焦期间新建 Git 仓库的情况。DirChanged 重绑监听、重扫复用的根节点。WinClosed/TabClosed 释放监听与防抖定时器并作废旧查询回调。
- 未展开目录的外部修改可能没有 fs_event，需等 FocusGained、切页、保存或手动 `r` 才更新，没有周期刷新时限；关闭 sidebar 不查询，其他 tabpage/source 保留的文件/index 监听仍可能触发查询。
- Files 的 Git 状态键相对仓库根目录，不是 cwd；折叠目录再次展开时需重扫，不能依赖折叠期间已停止的监听。
- 查询使用 `--ignored=matching`，避免递归输出被忽略目录中的每个文件；Files 的忽略标记需继承最近的 ignored 祖先，不能仅查当前路径。
- devicons 已缓存、fullname popup 复用 buffer/window、suffix 用 `right_align` virt_text — 不要退化。
- fullname popup 按 sidebar 的实际 `textoff` 对齐，沿用 `leftcol` 横向视口；不要用固定空格模拟边距，也不要在搜索触发横向滚动后从行首重画选中行。

## 集成点

- `core/filetree.lua` 的 `Plugins` / `SwapFiles` / `TimeMachine` 命令经 `ext-config.lua` 的 sidebar 条目首次加载，在 `setup()` 后注册；通过 `open_tab(files, { no_toggle = true, focus = false })` 展示目标目录并保留调用窗口焦点。
- `ext-loader.lua`：懒加载触发键。**新增或修改全局快捷键时，必须同步更新 `ext-loader.lua` 的 `keys` 列表，否则按键不会触发模块加载，快捷键不生效。**
- `ext/bufferline.lua`、`core/statusline.lua`、`ext/statuscol.lua`：Sidebar filetype 注册

## 测试

- `cd vim && ./tests/run-tests.sh` 跑全部 sidebar 测试：
  - `state_spec.lua` — per-tab schema / 隔离 / cleanup
  - `spec.lua` — git status 解析、render_tree、live_filter 纯逻辑
  - `interactive_spec.lua` — files source 的 cd/DirChanged/back/forward 状态机
  - `full_name_spec.lua` — 真实 UI 下长名称浮窗的边距、搜索横向滚动、宽字符、高亮与复用
  - `diff_preview_spec.lua` — `resolve_diff_targets` 映射、Git Changes 列表与预览窗口的 `c` / `d` 四种组合、真实单键输入不等待其他页的映射前缀
  - `parser_spec.lua` — `files_to_tree_nodes`、`git_root` 缓存自失效
  - `git_changes_spec.lua` — git_changes section 分类、restore_cursor 行为
  - `git_ops_spec.lua` — 真实 git 仓库下的 stage/discard/undo
- 新增 spec 时把测试基础设施统一从 `tests/sidebar/helpers.lua` 拿（`make_runner` / `eq` / `dump` / `color`），不要再各自重复定义。
- 测试公开依赖的稳定 API：
  - `sources.files._build_git_status_map`、`sources.files._git_status_to_glyph`、`sources.files.find_file`、`sources.files.render`、`sources.files.cd_to_node`、`sources.files.cd_parent`、`sources.files.stop_watchers`
  - `sources.git_changes.update_sections_from_stdout`
  - `sources.git_changes.parser.git_root` / `parser.invalidate_root_cache` / `parser.files_to_tree_nodes`
  - `actions.diff_preview.resolve_diff_targets`
  - `init._on_dir_changed`
  - `actions.navigation.back / forward`
  - `state.tab` / `state.tab_for` / `state.cleanup_closed_tabs`、`state.files.*`、`state.pwd_stack`、`state.pwd_forward_stack`
