# Git 模块工作指引

## 模块职责

提供 git 相关的增强功能，当前主要实现 line log 查看。

## 目录结构

- `init.lua`: 模块入口，注册按键映射
- `line-log/`: 行级 git log 子模块
  - `init.lua`: Neovim 入口，负责 session、窗口、buffer、prefetch 调度与 UI 驱动
  - `core.lua`: 纯算法与 git 历史收集核心，负责 revision/path 链、tracker 初始化与 block 推进；测试与运行时共用
  - `blob-store.lua`: 批量加载并缓存 `rev:file` 内容，供测试与运行时共用
  - `block.lua`: Block 类与 diff 生成（纯算法，不依赖 state）
  - `ui.lua`: 窗口、buffer、statusline、高亮、keymaps；直接消费 `state.tracker`

## 功能说明

### Line Log (`<leader>gl` visual 模式)

1. Visual 模式选中代码行后按 `<leader>gl`
2. 底部 split 窗口显示影响选中行的 commit 列表
3. 异步逐版本加载，窗口名称显示加载进度
4. 在 commit 行按 `<CR>` 右侧 vsplit 显示该 commit 对选中行的 diff；Visual 选中多个 commit 后按 `<CR>` 显示聚合 diff

### 技术要点

- **不使用 `git log -L`**，采用 IntelliJ IDEA 的内容追踪算法
- 算法流程：
  1. 先从当前路径开始，用 `git log --name-status --full-history --simplify-merges -- <path>` 收集当前路径的 revision 链
  2. 遇到 `A` commit 时，再用 `git show -M --name-status <commit> -- <path>` 探测 rename；若命中则把旧路径继续入队，构造完整 revision/path 链
  3. 对每个 `rev:file` 用 `git cat-file --batch` 按 100 个 revision 一批异步预取完整内容，并缓存；首批就绪后立即开始显示，剩余批次后台继续补
  4. `Block.create_previous_block()` 对比相邻版本内容，反向推导选中块在上一版本的位置
  5. 只显示内容实际变化的 commit，包括 block 从非空变为空前的最后一个 revision
- `core.lua` 同时提供同步与异步两套入口：
  - 同步入口给测试使用，避免在 spec 内复制一套算法实现
  - 异步入口给运行时使用，避免阻塞 Neovim UI
- `Block` 类：封装行内容和范围，`create_previous_block()` 实现位置追踪
  - 内部使用 0-based exclusive range `[start, end)` 对齐 IDEA 的 `Block.java`
  - vim.diff 返回的 1-based 索引需特殊转换：当 count=0（纯插入/纯删除）时，start 直接使用（不减 1）
  - `content_equals()` 使用严格逐行比较，对齐 IDEA 的 `getLines().equals()`
- `vim.diff()` 配置：
  - `algorithm = 'histogram'`：IDEA 的 ByLine diff 最接近 histogram/patience 算法；默认 myers 会产生过大的 hunk 导致 block 过早变空
  - `ignore_whitespace = true`：对齐 IDEA 的 `ComparisonPolicy.IGNORE_WHITESPACES`
- `vim.system()` 异步执行，避免阻塞
- 窗口关闭时 `BufWipeout` autocmd 触发 `job:kill()` 停止进程
- commit 列表格式：`%h %ad %s`，日期精确到秒
- 高亮：commit hash 用 `Number`，日期用 `Comment`

### 测试约定

- `vim/tests/line-log_spec.lua` 负责 line-log 算法测试，当前同时覆盖：
  - 现有 dotfiles 仓库里的固定 commit/文件/行段 case
  - 运行时动态创建的临时 git 仓库 fixture
- 临时 fixture 定义位于 `vim/tests/line-log-fixtures.lua`，仓库本体在测试运行时创建到系统临时目录，不把 `.git` fixture 提交进仓库
- 如果修改 revision/path 链、rename 处理、tracker 推进或 `Block` 交互，必须至少跑：
  - `cd vim && ./tests/run-tests.sh`
  - `cd vim && nvim --headless '+qa'`

### 与 `git log -L` 的区别

| | `git log -L` | 当前实现 |
|---|---|---|
| 追踪方式 | 行号 | 内容 |
| 重构影响 | 行号漂移导致结果错乱 | 准确追踪内容移动 |
| 性能 | 快（git 内部优化） | 需加载每个版本文件 |

## 按键映射

| 模式 | 按键 | 功能 |
|------|------|------|
| x | `<leader>gl` | 显示选中行的 commit 历史 |
| n (log buf) | `<CR>` | 显示当前 commit 的 diff |
| x (log buf) | `<CR>` | 显示选中多个 commit 的聚合 diff |

## 依赖

- 无外部插件依赖
- 需要 git 命令行工具

## 懒加载

通过 `ext-loader.lua` 注册，首次按 `<leader>gl` 时加载。
