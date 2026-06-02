# Tree Sidebar 工作指引

## 适用范围
- `vim/lua/lu5je0/ext/tree-sidebar/` 下的自定义树形侧边栏插件，替代 nvim-tree。
- 顶部 winbar 显示四个 tab：Files、Git Changes、Buffers、Symbols。

## 目录结构

```
tree-sidebar/
├── init.lua           -- 入口、setup、全局快捷键
├── config.lua         -- 所有配置：图标、highlight、tabs、宽度等
├── state.lua          -- per-tab 状态（metatable 按 tabpage 隔离）
├── window.lua         -- 窗口生命周期、fullname 浮窗
├── tabs.lua           -- winbar 渲染、tab 切换
├── keymaps.lua        -- 共享 + per-tab 快捷键管理
├── render.lua         -- 通用树渲染引擎
├── sources/
│   ├── files.lua          -- 文件树
│   ├── git_changes.lua    -- Git Changes
│   ├── buffers.lua        -- Buffers
│   └── symbols.lua        -- LSP Symbols
└── actions/
    ├── file_ops.lua       -- 文件操作（含剪贴板标记）
    ├── git_ops.lua        -- Git 操作（调用 git/common/git-ops.lua）
    ├── navigation.lua     -- cwd 历史 back/forward
    ├── preview.lua        -- 预览控制器
    └── diff_preview.lua   -- diff 预览
```

外部共享：`ext/git/common/git-ops.lua`（sidebar 和 git-status 共用的日志/undo/git 工具）

## Nerd Font 图标

- `config.lua` 中包含 Nerd Font 图标字符（tab label、folder icon、git glyph、section arrow、symbol kind icon）。
- **不要用 Edit 工具直接编辑config.lua**，多字节 UTF-8 匹配容易失败，请用合适的命令修改。

## 改动规则

- 渲染逻辑统一在 `render.lua`，不在各 source 重复。
- 新增 source：导出 `render()`、`keymaps()`，在 `config.lua` 的 `tabs` 表注册。
- 快捷键区分共享（`keymaps.lua` 的 `apply_shared()`）和 per-tab（source 的 `keymaps()`）。
- git 工具统一用 `git-ops.lua`，不要重复实现。
- 异步回调中访问 `state.xxx` 前先捕获 table 引用，避免 per-tab 代理写入错误 tab。
- 初始化逻辑统一走 `init_sidebar()`，不要在各入口函数重复。

## 性能规则

- **render 路径禁止同步外部命令**。git 数据通过异步预加载，render 只读缓存。
- **改动涉及 render、CursorMoved、高频 autocmd 时，必须提前告知用户性能影响。**
- `BufWritePost`/`FocusGained` 共享一次 `git status`，不要拆成多次。
- devicons 已缓存、fullname popup 复用 buffer/window、suffix 用 `right_align` virt_text — 不要退化。

## 集成点

- `ext-loader.lua`：`<leader>e/E/fe/fg/gs/fb/fs` 懒加载
- `ext/bufferline.lua`、`core/statusline.lua`、`ext/statuscol.lua`：TreeSidebar filetype 注册
