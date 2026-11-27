# Sidebar 工作指引

## 适用范围
- `vim/lua/lu5je0/ext/sidebar/` 下的自定义树形侧边栏插件，替代 nvim-tree。
- 顶部 winbar 默认依次显示 Files、Changes、Symbols；History / Buffers 是临时页签，快捷键打开后显示，关闭 Sidebar 后移除。左右键仅遍历可见页签，每次最多显示三个。

## 目录结构

```
sidebar/
├── init.lua           -- 入口：setup / toggle / focus / open_tab / locate_in_tab / _on_dir_changed
├── config.lua         -- 配置：图标、highlight、tabs、宽度；M.apply_highlights() 集中应用
├── state.lua          -- per-tab 状态（metatable 按 tabpage 隔离），new_tab_state() 是 schema 单一来源
├── lifecycle.lua      -- source enter / leave / locate / dispose，异步归属与统一关闭清理
├── git_status.lua     -- 单次异步 git status，按 tab 更新 Files/Git Changes 缓存并合并刷新请求
├── watcher.lua        -- 展开目录/Git 元数据 fs_event 与资源释放（无定时轮询）
├── window.lua         -- 窗口生命周期、guicursor
├── full_name.lua      -- 长文件名浮窗（CursorMoved/WinScrolled 触发）
├── tabs.lua           -- winbar 渲染、tab 切换
├── keymaps.lua        -- 共享 + per-tab 快捷键管理
├── folds.lua          -- 折叠键定义、已加载子树的批量折叠与展开
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
│   │   ├── expand.lua        -- 分批递归展开与取消（per-tab expand_job）
│   │   ├── git.lua           -- build_status_map / status_to_glyph / is_git_item
│   │   ├── live_filter.lua   -- 过滤 overlay（per-tab buf/win/closing 在 state.files._live_filter）
│   │   └── info.lua          -- show_file_info 浮窗
│   ├── git_changes.lua       -- 兼容 shim → sources.git_changes.init
│   ├── git_changes/
│   │   ├── init.lua          -- git_changes source 门面
│   │   ├── parser.lua        -- parse_git_status / files_to_tree_nodes / git_root 缓存（自失效）
│   │   └── locate.lua        -- do_locate / do_locate_first 实现
│   ├── history/
│   │   ├── init.lua          -- History source：提交树、勾选、历史 diff 目标与 open 入口
│   │   ├── author_filter.lua -- 第一行作者筛选与补全
│   │   ├── model.lua         -- 项目历史 / merge parent 文件列表的异步加载、缓存与取消
│   │   ├── core.lua          -- Git 日志与文件状态输出解析
│   │   └── tig.lua           -- Tig v2 提交图布局与颜色编号
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
- 修改图标后检查 diff，确认 UTF-8 字符完整。

## 架构约定

- 树渲染统一走 `render.render_tree(root_children, opts)`。渲染条目的 `item.parent` 指向同棵树的可见父行，`view.close_node` 沿这条链查找 `zc` 或 `zC` 的目标，并把光标停在该行。
- 合并目录行的 `item.node` 指向显示路径的末级目录，路径和文件操作都以它为准。`item.dir_chain` 仅在多级合并时存在，按从外到内的顺序记录整条链，供折叠和定位使用。分组与 stash 标题单独占行。
- buffer/窗口写入只走 `view.lua`（`flush` / `open_node` / `close_node` / `restore_cursor`）；`render.lua` 仍 re-export 兼容旧调用。
- 展开接口的 `open.keep_cursor(item)` 控制是否保留光标；History commit、Changes 分组与 stash 节点展开后留在当前行，已展开时再次按 `l` 也保持不动；普通目录沿用进入子节点的行为。
- 每个 source 通过 `source_base.lua` 的 spec 表声明 `build / render_opts / decorate / post_flush / open / close`，共用渲染和折叠骨架。`zC` 从当前行代表的目录链首节点开始递归收起，可通过 `close.subtree` 钩子处理异步任务和持久折叠状态。
- History 只展示已提交历史，未提交改动由 Changes 展示。History 与其他 source 一样走 `source_base` → `render_tree` → `view.flush`；`sources/history/model.lua` 只负责异步加载和取消，History 专属解析和提交图算法集中在 `sources/history/`，与 source 的窗口操作分离。`git_style.lua` 共用 Changes/History 的树样式；预览 source 可声明 `preview_kind` 与 `preview_item()`，由共享 preview / diff_preview 管理浮窗；条目可通过 `preview_kind = "text"`、`lines`、`title` 提供文本预览，`text_preview` 管理 per-tab 浮窗及资源释放。
- 新增 source：在 `sources/` 下新增模块，导出 `render()` 与 `keymaps()`，在 `config.tabs` 表注册。可选接口为 `enter(ctx, opts)`、`leave(ctx)`、`locate(ctx, target)`、`dispose(ctx)`；未声明 `enter` 时回退到 `render()`。定位前需要校验或转换目标时提供 `prepare_locate(target)`，返回 false 中止；`init.locate_in_tab` 只分派接口，不包含具体 source 分支。
- `enter(ctx, opts)` 负责让当前页就绪，同页 `focus()` 与 `open_tab(..., { no_toggle = true })` 也会调用；同一次访问复用 ctx，直到 `leave` 才失效。hook 必须支持重复调用，可刷新数据，但应取消或复用已有任务，避免重复持有资源；`enter` 与 `leave` 的调用次数不必一一对应。
- 快捷键区分共享（`keymaps.apply_shared`）和 per-tab（source `keymaps()`）。树页签通过 `source.folds` 提供 `open` / `close` / `open_recursive` / `close_subtree` / `expand_all` / `collapse_all`，可选 `cancel` 供 `Esc` 调用。`folds.lua` 统一为这些操作生成按键和帮助，`source_base` 与 `view` 负责通用的折叠操作，来源负责加载、存储折叠状态及确定渲染范围。`zo` 只打开折叠，文件和符号跳转走 `l` 等导航键。
- source 快捷键只绑定当前页，切页时先移除全部 source 映射，再绑定当前页；不能把非当前页按键保留成空操作，避免 Files 的 `dd` / `cd` 使 Git Changes 的 `d` / `c` 等待后续输入。同页存在短键和长键前缀时，先注册长键、后注册短键，使短键的 `nowait` 优先匹配；覆盖已有映射不会改变查找顺序，必须先移除再注册，单空格预览不能等待双空格超时。
- git 工具统一用 `actions/git_ops.lua` → `ext/git/common/git-ops.lua`。
- 页面异步入口通过 `lifecycle.capture()` 或 hook 参数取得 `ctx`（state、tabpage、idx、generation）；回调读写 `ctx.state`，更新页面前检查 `lifecycle.is_current(ctx)`。离开页面、切 Neovim tab、关闭与切目录会使旧 context 失效，离开后再回到同页也不能接收旧结果。后台 Git 状态刷新保留独立的 tabpage 和 generation 检查，不依赖当前页面。
- 跨 tab 的资源（fs_event、timer、preview 等）放进 per-tab state，不要写成模块级 singleton；页面持有的资源由自己的 `leave` / `dispose` 释放。Symbols 请求取消函数、请求 generation 与光标跟随 timer 均属于 `state.symbols`，保持 30ms 防抖。
- per-tab schema 单一来源：所有 per-tab 字段必须在 `state.lua` 的 `new_tab_state()` 中显式声明，便于一处看清完整 shape；页面私有资源在 source 的 `dispose(ctx)` 中释放；`state.cleanup_closed_tabs` 只调用 `lifecycle.dispose`，不依赖具体 source 的实现。
- 初始化路径统一走 `init.init_sidebar`，不在各入口函数重复。
- 关闭 Sidebar 前按 source 保存完整窗口视图（含鼠标滚动后的 `topline`），重新打开时在 source 渲染后恢复；对已打开窗口执行 focus 不回放旧视图，定位入口仍以定位目标为准。
- 所有 sidebar autocmd 都进 `sidebar` augroup（`autocmds.lua` 集中注册），在 `setup` 时 `clear = true` 以防重复。
- Buffers source 通过 `core/buffer-modified.lua` 订阅 `modified` 变化，兼容约定见 `vim/AGENTS.md` 的「临时兼容」。

- 生命周期只经 `lifecycle` 分派：Sidebar 打开、切 source 和切回 Neovim tab 时 enter；离开时先使 context 失效，再关闭预览并调用 source.leave。实际窗口关闭成功后，显式关闭与外部 WinClosed 共用 close（再释放 watcher / Git 状态查询并重置临时页签）；E444 等关闭失败必须保留窗口归属、context 和资源；Neovim tab 销毁经 dispose 清理全部已加载 source，清理 hook 必须可重复调用。`config.tabs[].transient` 定义临时页，显示状态保存在 per-tab `visible_tabs`，不改动稳定的 source 索引。`config.tabs[].width` 可指定默认宽度，各页宽度在 `tab_widths` 中记忆；History 默认 50 列，窗口过小时限制为屏幕的 60%。

## 快捷键

- `<leader>gs` 打开/定位 Git Changes tab（`locate_in_tab('git_changes')`）。
- 每个 tabpage **首次**按 `<leader>gs` 进入 Git Changes 时，忽略当前 buffer，光标定位到第一个变更文件（`git_changes.locate_first_file`），由 per-tab `state.git_changes._first_located` 记录；之后同 tabpage 再按仍定位当前文件（`locate_file`）。

- Files、Changes、Symbols、History 支持 `zo` 展开一层、`zc` 折叠最近一层、`zO` 递归展开、`zC` 递归折叠当前节点及其子折叠，以及 `zR` / `zM`。叶子行上的 `zC` 使用最近的可折叠父节点，保留其外层和旁支的开合状态。在 Files 根标题上按 `zC` 收起标题下所有目录。文件树和符号树的 `zR` 展开整棵树。Files 递归展开分批扫描和渲染，遵循隐藏目录设置并跳过符号链接。`Esc` 保留已显示的内容并停止后续批次，切页、换目录或关闭 Sidebar 也会取消任务。
- Changes 的 `zR` 展开当前分组。Stashes 按需加载，异步结果按当前子折叠设置显示。History 的 `zO` 展开当前提交、parent 或目录，`zR` 展开光标所在提交的全部折叠，`zM` 收起全部提交。对单个提交操作时，只重绘该提交的行。
- Changes 离开时取消 stash 加载；没有缓存条目的列表与未加载完的 stash 文件节点恢复折叠，返回后可按 `l` 重试，已加载内容与展开状态保留。Symbols 进入时先同步渲染缓存或空状态，再发起请求，等待 LSP 时不能保留上一页内容。

- Git diff 的布局与 changes-only 独立保存：`d` 保留上下文偏好；`c` 在 single 模式切换完整上下文 / 改动附近 3 行，在 dual 模式展开 / 折叠未变化区域。Space 预览期间，在列表或预览窗口按 `d` / `c` 均立即使用已加载内容刷新，不重读文件；切换布局保留当前焦点所在区域。
- Diff 浮窗立即打开，读取完成后在原窗口填入内容。加载过程中可关闭、进入浮窗或切换布局；关闭后旧回调不得重开窗口。Sidebar 使用普通窗口折叠设置，避免预览创建时继承编辑器的 Tree-sitter 折叠，双栏加载完成后启用原生 diff 折叠。

- 普通模式 `<leader>gl` 打开 History；merge 展开后按全部 parent 分组，Parent 标题使用独立暖黄色 `SidebarHistoryParent`，文件 diff 比较所属 parent 与 merge 结果，组内目录折叠状态独立；首次展开异步加载并缓存，切页/关闭取消，返回恢复未完成任务，无变化显示 `No changes`；`h/l`、`zo/zc` 折叠/展开，目录默认展开，连续目录链合并显示，打开目录时自动展开仅有一个子目录的连续链，在出现分支、文件或空目录时停止；收起时整条合并显示的目录链一起关闭，分支以下手动折叠的子节点保持折叠；文件行 Enter 打开工作区文件；Space 在提交行预览元数据及变更文件列表，在文件行预览历史 diff，再按进入浮窗，`d` / `c` 与 Changes 共用偏好及已加载内容，光标移走关闭预览。`m` 勾选 commit（支持 Visual），`U` 清空、Enter 查看勾选的净变化；`K` 查看提交详情，`gG` 切换 Tig v2 提交关系图（按 tabpage 保存开关，复用已加载提交的图形缓存），`r` 刷新，`ga` 加载全部，`Z` 调整宽度；普通提交标题使用正常文字对比度，短 hash 为青色、日期为暖色；merge 提交的标题、hash 和日期统一使用灰色 `SidebarHistoryMerge` 弱化，展开箭头保持蓝色，日期靠右，名称按可用宽度用省略号截断并为状态保留空间，完整信息通过 `K` 查看。

## 高亮约定

- 全部 highlight 集中在 `config.highlights` 表（包括 `Sidebar*`、`GitChanges*`、`GitFileStatus*`），由 `init.setup` → `config.apply_highlights()` 应用。
- Diff 浮窗的单栏和双栏均使用直角边框，窗口底色跟随编辑区的 `Normal`。
- 单栏 diff 复用 `git/common/unified-diff-highlight.lua` 的行背景和源码语法高亮。
- History 的箭头、hash 与标题使用互不重叠的高亮区间，禁止同优先级叠色；Tig 图形使用上游 14 色 ANSI palette 顺序和蓝色提交节点，RGB 取当前 terminal_color 或标准 ANSI 回退，由 config.apply_highlights 集中注册。
- ColorScheme 切换时 `autocmds.lua` 会重新 apply。
- Changes 的折叠目录在右侧显示方括号状态汇总：Changes 按 XY 两列分别汇总，相同字符（含空格）保留，混合为 `*`；Staged / Unstaged 只显示对应列，Untracked 显示 `[?]`。汇总在建树时自底向上计算，使用独立 `git_summary` 字段，不给目录设置文件 `xy`；展开后隐藏，章节和 stash 标题不显示，History 不启用。具体字母和 `?` 沿用文件状态颜色，`*` 与括号同为灰色，后代含冲突时 `*` 为红色；目录名称保留现有样式和整目录删除高亮。
- Files 的折叠目录将 Git 状态汇总为单个 `●`，优先级为冲突 > 未暂存 > 未跟踪 > 已暂存；
  冲突用红色 `!`，未暂存用琥珀色、未跟踪用紫色、已暂存用蓝色。已展开目录不显示汇总，
  文件保留具体状态图标，被忽略的目录保留灰色 `◌`；目录汇总单独判断工作区状态，
  同一文件同时有已暂存与未暂存修改时按未暂存汇总。

## 性能规则

- **render 路径禁止同步外部命令**。git 数据通过异步预加载，render 只读缓存。
- History 展开、折叠及 merge parent 加载完成时只重绘所属提交的行；重新加载、切换提交图和窗口宽度变化时重绘全页。
- History 的 `ga` 加载全部提交时保留当前列表；完成后按提交和树节点恢复光标与视口，并保留仍在历史中的提交展开状态和勾选。
- History 的 `f` 在第一行按作者姓名或邮箱筛选，复用 Files 的筛选行样式。按 `Tab` 补全、回车应用（空输入清除）、`Esc` 取消。补全异步读取 HEAD 可达的作者，筛选在 Git 限制提交数量前执行，`ga` 加载所有匹配提交。筛选按 tabpage 和仓库保留，显式跳转到提交时清除。筛选后的关系图只连显示的直接 parent，历史 diff 仍使用实际 parent。
- render 路径不调用 `redraw` / `redrawstatus` 强制刷新屏幕，确保视图恢复前的中间画面不会显示；剪贴板状态栏刷新只在复制/剪切操作中执行，`apply_clipboard_mark` 仅更新高亮。
- 修改 render、CursorMoved 或高频 autocmd 时检查热路径开销；有明显性能影响时说明验证结果。
- 所有 Git 状态触发统一调用 `git_status.lua`，由它执行一次 `git status` 并分发给 Files 与 Git Changes；不要在 source 或 autocmd 中另起查询。
- Git 查询使用 `--no-optional-locks` 避免自身写 index 触发监听回路；每个 tabpage 最多一个在途查询，查询期间的刷新请求合并为后续补查，不按时间窗口丢弃事件。
- `watcher.lua` 监听已展开目录与实际 gitdir（支持 worktree、无 index 的新仓库），只做事件防抖，不做定时轮询。刷新只扫描缓存树的展开目录，目录结构和 Git 输出均未变化时不重画。
- 打开 sidebar、切 source、返回 tabpage、FocusGained 和文件保存/重载时补刷；FocusGained 同时同步监听，覆盖离焦期间新建 Git 仓库的情况。DirChanged 重绑监听、重扫复用的根节点。WinClosed/TabClosed 释放监听与防抖定时器并作废旧查询回调。
- 未展开目录的外部修改可能没有 fs_event，需等 FocusGained、切页、保存或手动 `r` 才更新，没有周期刷新时限；关闭 sidebar 不查询，其他 tabpage/source 保留的文件/index 监听仍可能触发查询。
- Files 的 Git 状态键相对仓库根目录，不是 cwd；折叠目录再次展开时需重扫，不能依赖折叠期间已停止的监听。
- 查询使用 `--ignored=matching`，避免递归输出被忽略目录中的每个文件；Files 的忽略标记需继承最近的 ignored 祖先，不能仅查当前路径。
- devicons 使用缓存，fullname popup 复用 buffer/window，suffix 使用 `right_align` virt_text。
- fullname popup 按 sidebar 的实际 `textoff` 对齐，沿用 `leftcol` 横向视口；不要用固定空格模拟边距，也不要在搜索触发横向滚动后从行首重画选中行。

## 集成点

- `core/filetree.lua` 的 `Plugins` / `SwapFiles` / `TimeMachine` 命令经 `ext-config.lua` 的 sidebar 条目首次加载，在 `setup()` 后注册；通过 `open_tab(files, { no_toggle = true, focus = false })` 展示目标目录并保留调用窗口焦点。
- `ext-config.lua` 的 sidebar 条目声明懒加载触发键；新增或修改全局快捷键时同步维护其 `keys` 列表。
- `ext/bufferline.lua`、`ext/statusline/`、`ext/statuscol.lua`：Sidebar filetype 注册。Files 和 History 的筛选浮窗通过窗口变量 `statusline_parent` 沿用 Sidebar 的全局状态栏。

## 测试

- `cd vim && ./tests/run-tests.sh` 跑全部 sidebar 测试：
  - `state_spec.lua` — per-tab schema / 隔离 / cleanup
  - `lifecycle_spec.lua` — 统一定位、请求乱序、跨 tab 隔离、关闭与 E444、stash 取消后重试、Changes / Symbols 的折叠范围和任务清理
  - `spec.lua` — git status 解析、render_tree、live_filter 纯逻辑
  - `interactive_spec.lua` — files source 的 cd/DirChanged/back/forward 状态机
  - `full_name_spec.lua` — 真实 UI 下长名称浮窗的边距、搜索横向滚动、宽字符、高亮与复用
  - `scroll_spec.lua` — 真实鼠标滚轮与键盘翻页后关闭/重开恢复视图，逐帧检查没有中间位置闪动，并用真实按键验证 Files 筛选状态栏、递归展开和取消
  - `diff_preview_spec.lua` — `resolve_diff_targets` 映射、Git Changes 列表与预览窗口的 `c` / `d` 四种组合、真实单键输入、单栏跨 hunk 的语法高亮和行背景
  - `parser_spec.lua` — 独立 Git fixture 下的 `files_to_tree_nodes`、`git_root` 缓存自失效（同 cwd 出现嵌套仓库 / worktree、根标记删除后回退父仓库）
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
