# Tabline 工作指引

## 适用范围
- `vim/lua/lu5je0/ext/tabline/` 下的自定义 bufferline 实现，替代 akinsho/bufferline.nvim。
- 通过 `vim.o.tabline` + `%!v:lua...` 纯 Lua 渲染。

## 目录结构

```
ext/tabline/
├── init.lua        -- 入口：setup()，导出 buffer_name_map
├── config.lua      -- 选项、offsets 表、keymap 注册（setup_keymaps 延迟到 vim.schedule）
├── highlights.lua  -- 动态颜色推导（derive_colors → apply）
├── state.lua       -- 模块级缓存：buffer_name_map、ordinal_to_buf、pick 状态
├── naming.lua      -- Untitled-N gap-fill 命名分配器
├── render.lua      -- 纯 tabline 字符串构建 + truncation + 鼠标点击 + tab 页指示器
├── offsets.lua     -- 检测左侧 sidebar 窗口，生成 offset 填充块
├── actions.lua     -- cycle / go_to_ordinal / close_left / close_right / close_others
├── pick.lua        -- 字母分配 + getcharstr 选择模式
├── commands.lua    -- 用户命令注册（延迟到 vim.schedule）
└── autocmds.lua    -- 单 augroup 'tabline'，事件触发 debounced refresh
```

`ext/bufferline.lua` 是兼容 shim：`require + setup()` + 返回模块。

## 架构约定

- **颜色动态推导**：`highlights.apply()` 从当前 colorscheme 的 `Normal`、`Comment`、`String`、`TabLineSel`、`DiagnosticError`、`WinSeparator` 读取颜色，经 `shade()` 计算后设置所有 `BufferLine*` 高亮组。`ColorScheme` autocmd 重新应用。
- **Devicon 组合高亮**：`render.lua` 为每个文件 icon 创建 `BufferLineIcon_<iconHl>_<tabHl>` 组（icon fg + tab bg）。`ColorScheme` 时通过 `clear_icon_hl_cache()` 清除缓存。
- **Truncation**：放不下时从两侧平衡裁剪，当前 buffer 始终保留。左/右显示 ` N <arrow> ` 标记。
- **Tab 页指示器**：多 tabpage 时右对齐显示可点击的 tab 编号。
- **Offset**：扫描 tabpage 左侧窗口，按 filetype 匹配 `config.offsets`，手动空格填充居中，末尾追加 `█` separator。宽度 = `win_width + 1`（含 window separator 列）。
- **懒加载**：`ext-config.lua` 通过 `lazy_load` 注册，`UIEnter` 事件触发 setup。setup 内同步执行 `highlights.apply` + `autocmds` + 设置 winbar；`commands` 和 `config.setup_keymaps` 延迟到 `vim.schedule`。

## Nerd Font 图标

- `render.lua` 包含 Nerd Font 图标字符（truncation arrows U+F0A8 / U+F0A9）。
- **不要用 Edit 工具直接编辑这些图标行**，多字节 UTF-8 匹配容易失败；需要时用 python/sed 写入。

## 兼容接口

- `require('lu5je0.ext.tabline').buffer_name_map`：被 `tree-sidebar/sources/buffers.lua` 读取以显示 Untitled-N 名称。修改 state.buffer_name_map 的结构时必须确认 sidebar 兼容。
- `require('lu5je0.core.buffers').valid_buffers()`：共享 buffer 列表（buflisted + is_valid），被 tabline、tree-sidebar、time-machine 共用。

## 按键映射

| 按键 | 功能 |
|------|------|
| `<leader>0` | Pick 模式（字母跳转） |
| `<leader>1..9` | 跳转到第 N 个 buffer |
| `<leader>to` | 关闭其他所有 buffer |
| `<leader>th` | 关闭左侧 buffer |
| `<leader>tl` | 关闭右侧 buffer |
| `<left>` | 切换到上一个 buffer |
| `<right>` | 切换到下一个 buffer |

## 维护注意

- 新增/修改高亮组：在 `highlights.apply()` 的 `groups` 表内操作，不要散落到其他文件。
- 改动 buffer 列表逻辑：确认 `core/buffers.lua` 的消费方（tree-sidebar、time-machine）不受影响。
- 改动 offset 逻辑：确认 sidebar 的 foldcolumn/signcolumn 宽度是否影响对齐。
- 改动 truncation 或 tab 指示器宽度计算时，两处必须同步（`tab_section_w` 估算 + 实际渲染）。
