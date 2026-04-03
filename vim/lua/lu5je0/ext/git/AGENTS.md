# Git 模块工作指引

## 模块职责

提供 git 相关的增强功能，当前主要实现 line log 查看。

## 目录结构

- `init.lua`: 模块入口，注册按键映射
- `line-log.lua`: 行级 git log 查看功能

## 功能说明

### Line Log (`<leader>gl` visual 模式)

1. Visual 模式选中代码行后按 `<leader>gl`
2. 底部 split 窗口显示影响选中行的 commit 列表
3. 异步分批加载（每批 20 条），窗口名称显示加载进度
4. 在 commit 行按 `<CR>` 右侧 vsplit 显示该 commit 对选中行的 diff
5. 按 `q` 关闭窗口

### 技术要点

- 使用 `git log -L<start>,<end>:<file>` 查询影响指定行的 commit
- `vim.system()` 异步执行，避免阻塞
- 分批加载：`-n 20 --skip <offset>`，上一批完成后立即加载下一批
- 窗口关闭时 `BufWipeout` autocmd 触发 `job:kill()` 停止进程
- commit 列表格式：`%h %ad %s`，日期精确到秒
- 高亮：commit hash 用 `Number`，日期用 `Comment`

## 按键映射

| 模式 | 按键 | 功能 |
|------|------|------|
| x | `<leader>gl` | 显示选中行的 commit 历史 |
| n (log buf) | `<CR>` | 显示当前 commit 的 diff |
| n (log/diff buf) | `q` | 关闭窗口 |

## 依赖

- 无外部插件依赖
- 需要 git 命令行工具

## 懒加载

通过 `ext-loader.lua` 注册，首次按 `<leader>gl` 时加载。
