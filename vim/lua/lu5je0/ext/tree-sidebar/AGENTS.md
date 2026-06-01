# Tree Sidebar 工作指引

## 适用范围
- 本文件适用于 `vim/lua/lu5je0/ext/tree-sidebar/` 目录下的自定义树形侧边栏插件。
- 该插件替代 nvim-tree，提供统一左侧面板，顶部 winbar 显示三个 tab：Files、Git Changes、Buffers。

## 目录结构

```
tree-sidebar/
├── init.lua        -- 入口：setup()、toggle()、focus()、open_tab()、locate_file()、全局快捷键
├── config.lua      -- 常量、highlight 定义、filetype、图标
├── state.lua       -- per-tab 状态：通过 metatable __index/__newindex 按 tabpage 隔离
├── window.lua      -- 侧边栏窗口生命周期：打开/关闭/resize/记住宽度/guicursor/winfixbuf
├── tabs.lua        -- winbar 渲染（支持鼠标点击）、tab 切换（保存/恢复光标）
├── keymaps.lua     -- 共享快捷键 + per-tab 快捷键注册/清理
├── render.lua      -- 通用树渲染引擎 + buffer 写入/highlight/virt_text 工具
├── sources/
│   ├── files.lua       -- 文件树 source（libuv fs_scandir、展开/折叠、git 叠加、dotfile 过滤、文件信息）
│   ├── git_changes.lua -- Git Changes source（porcelain 解析、分组、highlight）
│   └── buffers.lua     -- Buffers source（列出已打开 buffer、切换/关闭）
└── actions/
    ├── file_ops.lua       -- 文件操作：创建/重命名/删除/剪切/复制/粘贴（含剪贴板下划线标记）
    ├── git_ops.lua        -- Git 操作：stage/unstage/discard/undo（调用 git/common/git-ops.lua）
    ├── navigation.lua     -- cwd 历史栈 back/forward（带 root 缓存 + cursor 恢复）
    ├── preview.lua        -- 预览控制器：状态管理、toggle、enter、scroll
    └── diff_preview.lua   -- diff 预览实现：双窗口 diff、changes-only toggle
```

外部共享模块：
- `ext/git/common/git-ops.lua` -- git 日志/undo/run_git 工具（sidebar 和 git-status 共用）

## 核心设计

### 渲染引擎 (render.lua)
- `render_tree(nodes, opts)` 是通用树渲染函数，所有 source 共用。返回 `lines, items, highlights, virt_texts`。
- 支持的 opts：`filter`、`file_suffix`、`dir_suffix`、`get_dir_icon`、`item_data`、`compress_dirs`、`flat_depth`。
- `file_suffix`/`dir_suffix` 返回的第二个值如果是 table 则作为 `virt_text` 格式（`{{text, hl}, ...}`），是 string 则包装为单项。
- suffix 通过 `nvim_buf_set_extmark` + `virt_text_pos = 'right_align'` 渲染，固定在窗口右边缘。
- `compress_dirs=true` 时自动压缩单子目录链为 `a/b/c` 显示。
- `flat_depth` 控制到几层为止不加树线缩进（git_changes 用 `flat_depth=1`）。
- devicons 模块只 require 一次，后续复用缓存。

### 状态管理 (state.lua)
- **per-tab 隔离**：通过 `__index`/`__newindex` 元方法，`state.xxx` 自动路由到当前 tabpage 的数据。所有引用 `state.win`、`state.files` 等的代码无需感知多 tab。
- 全局字段（`pwd_stack`、`pwd_forward_stack`、`_is_jumping`、`_last_pushed_cwd`）不走代理，所有 tab 共享。
- `state.files.root` 是文件树根节点，`_root_cache` 按 cwd 缓存历史树，`_cursor_cache` 按 cwd 缓存光标位置。
- `state.git_changes._dir_states` 按 section 隔离目录展开状态，`_undo_stack` 存储 undo 历史。
- `TabClosed` 时调用 `cleanup_closed_tabs()` 清理无效 tab 的 state。

### Tab 系统 (tabs.lua + keymaps.lua)
- winbar 渲染 tab 栏，支持鼠标点击切换。
- 切换 tab 时保存/恢复光标位置，清理旧 tab 快捷键并注册新 tab 快捷键。
- 共享快捷键：`<left>`/`<right>` 切换、`1`/`2`/`3` 跳转、`q` 关闭、`Z` 切宽、`<esc>` 关闭预览/清除剪贴板、`?` 帮助。

### Files Source
- 使用 `vim.uv.fs_scandir` 按目录懒加载。
- `rescan_node()` 刷新时保留展开状态。
- cd 操作通过 `_root_cache` 缓存历史树，`_cursor_cache` 缓存光标位置，`<c-o>` 返回时恢复。
- Git 状态叠加通过异步 `git status --porcelain=v1 -z --ignored`，含目录级联传播（dirty > new > staged 优先级），ignored 不传播。
- `compress_dirs` 可通过 `zc` 切换，展开时自动沿单子目录链预展开。
- `K` 显示文件信息浮窗（不聚焦，光标上方/下方自适应）。
- 剪切/复制用独立 namespace 的下划线标记，paste/esc 后清除。

### Git Changes Source
- 解析 git status 分为 changes/staged/unstaged/untracked 四个 section。
- git 操作（stage/unstage/discard/undo）委托给 `actions/git_ops.lua`，带日志和 undo 栈。
- `[XY]` 状态用 per-char virt_text 渲染，固定在右边缘。
- 每个 section 独立的 `_dir_states` 避免跨 section 展开干扰。
- `compress_dirs=true`、`flat_depth=1` 压缩纯目录链且 section 子节点无缩进。
- `<leader>fe` 可从文件/目录节点跳转到 files tab 定位。

### Buffers Source
- 从 `vim.api.nvim_list_bufs()` 获取已打开 buffer。
- 转为 file 类型节点交给通用渲染器。
- 自动监听 `BufAdd`/`BufDelete`/`BufWipeout`/`BufModifiedSet` 刷新。

### Preview 系统
- 文件预览：`actions/preview.lua` 控制状态，通过 `core/ui.lua` 的 scratch buffer 渲染（不触发 LSP）。
- Diff 预览：`actions/diff_preview.lua` 双窗口 diff，支持 `d` 切换 changes-only（`foldenable`/`foldlevel`）。
- 两次空格进入预览/diff 窗口，`q` 返回 sidebar。BufLeave 自动关闭（排除 diff/popup 窗口）。
- 二进制文件检测（前 512 字节查 null），binary 显示 `[Binary file]`。

## 集成点
- `ext-loader.lua`：注册 `<leader>e`、`<leader>E`、`<leader>fe`、`<leader>gs`、`<leader>fb` 懒加载。
- `plugins.lua`：nvim-tree 已注释掉。
- `ext/bufferline.lua`：offsets 中有 `TreeSidebar` 条目。
- `core/statusline.lua`：`special_filetypes` 中有 `TreeSidebar`。
- `ext/statuscol.lua`：`ft_ignore` 中有 `TreeSidebar`。

## 改动规则
- 修改渲染逻辑统一在 `render.lua`，不要在各 source 里重复实现树渲染。
- 新增 source 时遵循现有模式：导出 `render()`、`keymaps()` 函数，在 `config.lua` 的 `tabs` 表中注册。
- 修改快捷键时注意共享 vs per-tab 区分：共享键在 `keymaps.lua` 的 `apply_shared()`，per-tab 键由 source 的 `keymaps()` 返回。
- 修改展开/折叠逻辑时确保状态持久化到对应的 `_dir_states` 或 `_root_cache`。
- git 操作工具（`run_git`、`hash_file`、`log_batch`、undo 栈）统一使用 `ext/git/common/git-ops.lua`，不要在 sidebar 代码中重复实现。
- 异步回调中访问 `state.xxx` 要注意 per-tab 代理：在发起异步操作前捕获 table 引用（如 `local tab_files = state.files`），回调中操作捕获的引用，避免写入错误的 tab。

## 性能规则
- **render 路径禁止同步 git/外部命令**：`render()` 函数中不得调用 `vim.system():wait()` 或 `vim.fn.system()`。git 数据通过异步 `refresh_git_status` 预加载，render 只读缓存。
- **如果改动涉及 render 路径、CursorMoved 回调、或高频 autocmd，必须提前告知用户可能的性能影响**。
- devicons 模块已缓存（`render.lua` 顶部），不要改回 `pcall(require)` per-call。
- `BufWritePost`/`FocusGained` 共享一次 `git status` 调用喂给 files 和 changes 两个 tab，不要拆成两次。
- fullname popup（`window.lua`）复用 buffer 和 window，不要每次 CursorMoved 创建/销毁。
- suffix 使用 `right_align` virt_text，不要用 padding 空格拼接到行文本中。

## 验证
- 最小验证：`cd vim && nvim --headless -c "lua require('lu5je0.ext.tree-sidebar').setup(); require('lu5je0.ext.tree-sidebar').toggle({focus=true})" -c "qa"`
- 切换 tab：验证三个 source 都能正确 render。
- cd + back/forward：验证展开状态保留。
- git changes 的 stage/unstage/discard：验证操作后正确刷新。
