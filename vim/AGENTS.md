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
- `lua/lu5je0/misc/`: 独立功能模块与自定义工具，例如 IME、clipboard、timestamp、translator、json-helper。
- `lua/lu5je0/lang/`: 轻量通用工具函数。
- `ftplugin/`, `syntax/`, `indent/`: 文件类型定制。
- `lsp/`: 独立语言服务器配置文件。
- `patches/`: 对上游插件的补丁文件，和 `plugins.lua` 中的 `patches = { ... }` 声明联动。
- `tests/`: 当前仓库内的自动化测试。现有入口覆盖 `cron-parser`、`line-log`、`project-log` 与 `sidebar`，并按功能子目录组织。
- `lib/` 下的 native 依赖优先按平台子目录组织；如果调整其落点，需要同时检查 Neovim 配置、外部消费脚本和构建同步逻辑。

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
- `lua/lu5je0/misc/tui-bridge/`、`lua/lu5je0/misc/im/`、`lua/lu5je0/misc/clipboard/` 含平台相关逻辑。
- `vim/lib/macos/bin/tui_bridge` 与 `vim/lib/windows/bin/tui_bridge` 来自 `submodule/tui-bridge` 构建产物；平台由目录区分，不再靠文件名后缀区分。不要在 Neovim 侧文档中把它们描述成普通 Lua 模块。
- `lua/lu5je0/core/native.lua` 负责解析 `vim/lib/` 下的 native 资源路径；新增平台二进制或动态库时，优先复用这个入口，不要在业务模块里继续硬编码 `stdpath('config') .. '/lib/...'`。
- 如果任务改动了桥接协议、IME 行为、剪贴板桥接或二进制同步流程，必须同步检查 `submodule/tui-bridge/AGENTS.md`。

## 测试与验证
- 最小启动验证：
  - `cd vim && nvim --headless '+qa'`
- 当前自动化测试入口：
  - `cd vim && ./tests/run-tests.sh`
- `tests/run-tests.sh` 通过 `luajit` 运行 `tests/cron/spec.lua`（要求设置 `DOTFILES_ROOT`），并通过 `nvim --headless -u NONE -l` 运行 `tests/line-log/spec.lua`、`tests/project-log/spec.lua`、`tests/sidebar/state_spec.lua`、`tests/sidebar/spec.lua`、`tests/sidebar/interactive_spec.lua`、`tests/sidebar/diff_preview_spec.lua`、`tests/sidebar/parser_spec.lua`、`tests/sidebar/git_changes_spec.lua`、`tests/sidebar/git_ops_spec.lua`。
- 如果你新增了独立 Lua 功能且具备稳定输入输出，优先补到 `tests/`，不要只依赖手动打开 Neovim 验证。
- 如果改动只覆盖某个懒加载模块，至少补一次对应命令、按键或事件的首次加载路径验证。

## 提交流程建议
- 改完入口或模块后，先跑 `nvim --headless '+qa'`，尽可能不在沙箱内运行，确认没有直接语法错误或 require 失败。
- 改插件补丁时，确认补丁文件、插件声明、运行时行为三者一致。
- 改平台相关能力时，在提交说明里明确受影响平台与未验证平台。

## 已知事实
- 仓库根 README 将该目录视为 `neovim` 配置的一部分。
- 当前仓库在 `vim/` 目录下使用 `stylua.toml`，说明 Lua 格式化约定已本地化到该目录。
- 当前没有覆盖整个配置的完整端到端测试；很多能力仍依赖启动验证和定向手工验证。
