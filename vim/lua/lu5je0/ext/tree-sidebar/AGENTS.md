# Tree Sidebar 工作指引

## 适用范围
- `vim/lua/lu5je0/ext/tree-sidebar/` 下的自定义树形侧边栏插件，替代 nvim-tree。
- 顶部 winbar 显示四个 tab：Files、Git Changes、Buffers、Symbols。

## 目录结构

```
tree-sidebar/
├── init.lua           -- 入口：setup / toggle / focus / open_tab / locate_in_tab / _on_dir_changed
├── config.lua         -- 配置：图标、highlight、tabs、宽度；M.apply_highlights() 集中应用
├── state.lua          -- per-tab 状态（metatable 按 tabpage 隔离），M.tab() 显式取当前 tab table
├── window.lua         -- 窗口生命周期、guicursor、fullname 浮窗
├── tabs.lua           -- winbar 渲染、tab 切换
├── keymaps.lua        -- 共享 + per-tab 快捷键管理
├── autocmds.lua       -- 集中注册到 `tree-sidebar` augroup（DirChanged / TabClosed /
│                          ColorScheme / BufWritePost+FocusGained / BufEnter+LspAttach /
│                          buffers source 自动刷新）
├── render.lua         -- 纯渲染引擎：tree → lines/items/highlights/virt_texts
├── view.lua           -- buffer/window 写入：flush / open_node / close_node / restore_cursor
├── source_base.lua    -- Source 基类：build / render_opts / decorate / post_flush / open / close
├── sources/
│   ├── files.lua             -- 兼容 shim → sources.files.init
│   ├── files/
│   │   ├── init.lua          -- files source 门面（render / open_node / find_file / cd_* / keymaps）
│   │   ├── tree.lua          -- 节点 / scan_dir / ensure_children / rescan / rel_to_cwd / make_filter
│   │   ├── watcher.lua       -- fs_event 增量挂载
│   │   ├── git.lua           -- build_status_map / status_to_glyph / refresh / is_git_item
│   │   └── info.lua          -- show_file_info 浮窗
│   ├── git_changes.lua       -- 兼容 shim → sources.git_changes.init
│   ├── git_changes/
│   │   ├── init.lua          -- git_changes source 门面
│   │   ├── parser.lua        -- parse_git_status / files_to_tree_nodes / git_root 缓存
│   │   └── locate.lua        -- do_locate 实现
│   ├── buffers.lua           -- Buffers source（含 setup_auto_refresh）
│   └── symbols.lua           -- LSP Symbols source
└── actions/
    ├── file_ops.lua          -- 文件操作（含剪贴板标记）
    ├── git_ops.lua           -- Git 操作（调用 git/common/git-ops.lua）
    ├── navigation.lua        -- cwd 历史 back/forward
    ├── preview.lua           -- 预览控制器
    └── diff_preview.lua      -- diff 预览
```

外部共享：`ext/git/common/git-ops.lua`（sidebar 和 git-status 共用的日志/undo/git 工具）

## Nerd Font 图标

- `config.lua` 中包含 Nerd Font 图标字符（tab label、folder icon、git glyph、section arrow、symbol kind icon）。
- **不要用 Edit 工具直接编辑这些图标行**，多字节 UTF-8 匹配容易失败，请用合适的命令修改；普通字段（如 `M.highlights`）可用 Edit。

## 架构约定

- 树渲染统一走 `render.render_tree(root_children, opts)`，不在各 source 重复实现。
- buffer/窗口写入只走 `view.lua`（`flush` / `open_node` / `close_node` / `restore_cursor`）；`render.lua` 仍 re-export 兼容旧调用。
- 每个 source 通过 `source_base.lua` 的 spec 表声明 `build / render_opts / decorate / post_flush / open / close / keymaps`，不再各自手写 render/open_node/close_node 骨架。
- 新增 source：在 `sources/` 下新增模块，导出 `render()` 与 `keymaps()`，在 `config.tabs` 表注册即可。
- 快捷键区分共享（`keymaps.apply_shared`）和 per-tab（source `keymaps()`）。
- git 工具统一用 `actions/git_ops.lua` → `ext/git/common/git-ops.lua`。
- 异步回调中访问 `state.xxx` 前先捕获 table 引用（如 `local ts = state.tab()` 或 `local tab_files = state.files`），避免 per-tab 代理在错误 tabpage 写入。
- 初始化路径统一走 `init.init_sidebar`，不在各入口函数重复。
- 所有 sidebar autocmd 都进 `tree-sidebar` augroup（`autocmds.lua` 集中注册），在 `setup` 时 `clear = true` 以防重复。

## 高亮约定

- 全部 highlight 集中在 `config.highlights` 表（包括 `TreeSidebar*`、`GitChanges*`、`GitFileStatus*`），由 `init.setup` → `config.apply_highlights()` 应用。
- ColorScheme 切换时 `autocmds.lua` 会重新 apply。

## 性能规则

- **render 路径禁止同步外部命令**。git 数据通过异步预加载，render 只读缓存。
- **改动涉及 render、CursorMoved、高频 autocmd 时，必须提前告知用户性能影响。**
- `BufWritePost`/`FocusGained` 共享一次 `git status`，并在 `autocmds.lua` 内分发给 files 与 git_changes，不要拆成多次。
- devicons 已缓存、fullname popup 复用 buffer/window、suffix 用 `right_align` virt_text — 不要退化。

## 集成点

- `ext-loader.lua`：懒加载触发键。**新增或修改全局快捷键时，必须同步更新 `ext-loader.lua` 的 `keys` 列表，否则按键不会触发模块加载，快捷键不生效。**
- `ext/bufferline.lua`、`core/statusline.lua`、`ext/statuscol.lua`：TreeSidebar filetype 注册

## 测试

- `cd vim && ./tests/run-tests.sh` 跑 `spec.lua`、`interactive_spec.lua`、`diff_preview_spec.lua`。
- `git_changes_spec.lua` 与 `git_ops_spec.lua` 当前未在 run-tests.sh 中，但在改动 git_changes / git_ops 时应手动跑：
  - `nvim --headless -u NONE -l tests/tree-sidebar/git_changes_spec.lua`
  - `nvim --headless -u NONE -l tests/tree-sidebar/git_ops_spec.lua`
- 测试公开依赖的稳定 API：
  - `sources.files._build_git_status_map`、`sources.files._git_status_to_glyph`、`sources.files.find_file`、`sources.files.render`、`sources.files.cd_to_node`、`sources.files.cd_parent`、`sources.files.stop_watchers`
  - `sources.git_changes.update_sections_from_stdout`
  - `actions.diff_preview.resolve_diff_targets`
  - `init._on_dir_changed`
  - `actions.navigation.back / forward`
  - `state.files.*`、`state.pwd_stack`、`state.pwd_forward_stack`
