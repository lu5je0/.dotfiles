# Tree Sidebar 工作指引

## 适用范围
- 本文件适用于 `vim/lua/lu5je0/ext/tree-sidebar/` 目录下的自定义树形侧边栏插件。
- 该插件替代 nvim-tree，提供统一左侧面板，顶部 winbar 显示三个 tab：Files、Git Changes、Buffers。

## 目录结构

```
tree-sidebar/
├── init.lua        -- 入口：setup()、toggle()、focus()、locate_file()、全局快捷键
├── config.lua      -- 常量、highlight 定义、filetype、图标
├── state.lua       -- 全局状态：win/buf 引用、active_tab、光标位置、cwd 栈
├── window.lua      -- 侧边栏窗口生命周期：打开/关闭/resize/记住宽度/guicursor
├── tabs.lua        -- winbar 渲染、tab 切换（保存/恢复光标）
├── keymaps.lua     -- 共享快捷键 + per-tab 快捷键注册/清理
├── render.lua      -- 通用树渲染引擎 + buffer 写入/highlight 工具
├── sources/
│   ├── files.lua       -- 文件树 source（libuv fs_scandir、展开/折叠、git 叠加、dotfile 过滤）
│   ├── git_changes.lua -- Git Changes source（porcelain 解析、分组、stage/unstage/discard）
│   └── buffers.lua     -- Buffers source（列出已打开 buffer、切换/关闭）
└── actions/
    ├── file_ops.lua    -- 文件操作：创建/重命名/删除/剪切/复制/粘贴
    ├── navigation.lua  -- cwd 历史栈 back/forward（带 root 缓存）
    └── preview.lua     -- 浮动预览（委托 core/ui.lua）
```

## 核心设计

### 渲染引擎 (render.lua)
- `render_tree(nodes, opts)` 是通用树渲染函数，所有 source 共用。
- 支持的 opts：`filter`、`file_suffix`、`dir_suffix`、`get_dir_icon`、`item_data`、`compress_dirs`。
- `compress_dirs=true` 时自动压缩单子目录链为 `a/b/c` 显示。
- 第一级节点无连接符前缀，第二级开始有 `│`/`└` 树线。
- depth 参数（非 prefix 长度）判断是否为 root level。

### 状态管理 (state.lua)
- 全局单例，所有模块通过 require 共享。
- `state.files.root` 是文件树根节点，`_root_cache` 按 cwd 缓存历史树。
- `state.git_changes._dir_states` 按 section 隔离目录展开状态。
- `state.pwd_stack` / `state.pwd_forward_stack` 管理 cwd 历史。

### Tab 系统 (tabs.lua + keymaps.lua)
- winbar 渲染 tab 栏。
- 切换 tab 时保存/恢复光标位置，清理旧 tab 快捷键并注册新 tab 快捷键。
- 共享快捷键：`<left>`/`<right>` 切换、`1`/`2`/`3` 跳转、`q` 关闭、`Z` 切宽。

### Files Source
- 使用 `vim.uv.fs_scandir` 按目录懒加载。
- `rescan_node()` 刷新时保留展开状态。
- cd 操作（`cd_to_node`/`cd_parent`/`cd_home`/`back`/`forward`）通过 `_root_cache` 缓存并恢复历史树。
- Git 状态叠加通过异步 `git status --porcelain=v1 -z`。

### Git Changes Source
- 解析 git status 分为 changes/staged/unstaged/untracked 四个 section。
- changes section 合并所有文件（每路径一次），与 `<leader>gs` 的 Changes 对齐。
- 颜色使用 `GitChanges*` 和 `GitFileStatus*` 高亮组（与 ext/git/git-status/ui.lua 一致）。
- 每个 section 独立的 `_dir_states` 避免跨 section 展开干扰。
- `compress_dirs=true` 压缩纯目录链。

### Buffers Source
- 从 `vim.api.nvim_list_bufs()` 获取已打开 buffer。
- 转为 file 类型节点交给通用渲染器。
- 自动监听 `BufAdd`/`BufDelete`/`BufWipeout`/`BufModifiedSet` 刷新。

## 集成点
- `ext-loader.lua`：注册 `<leader>e`、`<leader>E`、`<leader>fe` 懒加载。
- `plugins.lua`：nvim-tree 已注释掉。
- `ext/bufferline.lua`：offsets 中有 `TreeSidebar` 条目。
- `core/statusline.lua`：`special_filetypes` 中有 `TreeSidebar`。
- `ext/statuscol.lua`：`ft_ignore` 中有 `TreeSidebar`。

## 改动规则
- 修改渲染逻辑统一在 `render.lua`，不要在各 source 里重复实现树渲染。
- 新增 source 时遵循现有模式：导出 `render()`、`keymaps()` 函数，在 `config.lua` 的 `tabs` 表中注册。
- 修改快捷键时注意共享 vs per-tab 区分：共享键在 `keymaps.lua` 的 `apply_shared()`，per-tab 键由 source 的 `keymaps()` 返回。
- 修改展开/折叠逻辑时确保状态持久化到对应的 `_dir_states` 或 `_root_cache`。

## 验证
- 最小验证：`cd vim && nvim --headless -c "lua require('lu5je0.ext.tree-sidebar').setup(); require('lu5je0.ext.tree-sidebar').toggle({focus=true})" -c "qa"`
- 切换 tab：验证三个 source 都能正确 render。
- cd + back/forward：验证展开状态保留。
- git changes 的 stage/unstage/discard：验证操作后正确刷新。
