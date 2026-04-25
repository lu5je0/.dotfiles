# Git 模块工作指引

## 模块职责

提供 git 相关的增强功能，当前主要实现 line log 与项目级 commit log 查看。

## 目录结构

- `init.lua`: 模块入口，注册按键映射
- `line-log/`: 行级 git log 子模块
  - `init.lua`: Neovim 入口，负责 session、窗口、buffer、prefetch 调度与 UI 驱动
  - `core.lua`: 纯算法与 git 历史收集核心，负责 revision/path 链、tracker 初始化与 block 推进；测试与运行时共用
  - `blob-store.lua`: 批量加载并缓存 `rev:file` 内容，供测试与运行时共用
  - `block.lua`: Block 类与 diff 生成（纯算法，不依赖 state）
  - `ui.lua`: 窗口、buffer、statusline、高亮、keymaps；直接消费 `state.tracker`
- `project-log/`: 项目级 commit log 子模块
  - `init.lua`: Neovim 入口，负责 session、git 命令、文件 diff 窗口与 keymaps
  - `core.lua`: 解析项目级 `git log --name-status` 输出
  - `graph.lua`: 维护 compact git graph 状态，解析 `git log --graph` 的 prefix 与 graph-only continuation 行并折叠成单行 graph
  - `ui.lua`: 渲染 commit 列表、文件树、图标、高亮与 statusline
  - `scheduler.lua`: CursorMoved 后的 diff preview 调度

## 功能说明

### Line Log (`<leader>gl` visual 模式)

1. Visual 模式选中代码行后按 `<leader>gl`
2. 底部 split 窗口显示影响选中行的 commit 列表
3. 异步逐版本加载，窗口名称显示加载进度
4. 在 log 窗口移动光标会自动在右侧 vsplit 预览当前 commit 对选中行的 diff
5. 在 log 窗口 Visual 选中多个 commit 会自动显示聚合 diff

### Project Log (`<leader>gl` normal 模式)

1. Normal 模式按 `<leader>gl`
2. 底部 split 窗口显示当前 git 仓库的 commit 列表，窗口高度约为当前窗口的 80%
3. 如果存在未提交改动，列表顶部显示 `local change` 伪 commit 节点
4. commit 行在最前方渲染 git graph 语义列：普通提交为 `o`，merge 提交为 `M─┐`，活动分支列为 `│`；graph 后保留当前 commit 文本格式
5. commit 节点默认折叠；打开 commit 时，内部目录树默认全部展开，只有单个子目录的连续目录链压缩成 `parent/child` 显示
6. 在 commit 行按 `l` / `<CR>` 展开节点，并把光标放到第一个可见子节点；在目录行按 `l` / `<CR>` 展开节点，并把光标放到第一个子节点
7. 在 commit 行按 `h` 折叠 commit；在展开目录行按 `h` 先折叠当前目录，在折叠目录或文件行按 `h` 折叠父节点
8. 光标移动到文件行时，右侧 vsplit 自动显示该 commit 对该文件的 diff；文件行 `<CR>` 可手动刷新
9. `d` / `D` 复用 line-log 的 changes-only 与 diff mode 偏好

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

- `vim/tests/line-log/spec.lua` 负责 line-log 算法测试，当前同时覆盖：
  - 现有 dotfiles 仓库里的固定 commit/文件/行段 case
  - 运行时动态创建的临时 git 仓库 fixture
- `vim/tests/project-log/spec.lua` 负责 project-log graph 渲染回归测试，固定复杂 merge / crossover 历史段的 compact graph 输出
- 临时 fixture 定义位于 `vim/tests/line-log/fixtures.lua`，仓库本体在测试运行时创建到系统临时目录，不把 `.git` fixture 提交进仓库
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
| n | `<leader>gl` | 显示当前仓库的项目 commit log |
| x | `<leader>gl` | 显示选中行的 commit 历史 |
| n (source buf) | `<leader>gL` | 显示当前文件的 commit 历史 |
| n (log buf) | `j` / `k` 等移动 | 自动预览当前 commit 的 diff |
| x (log buf) | Visual 选择 | 自动预览选中 commit 范围的聚合 diff |
| n (project log buf) | `l` / `<CR>` on commit | 展开 commit 文件树并默认展开全部目录，跳到第一个文件 |
| n (project log buf) | `l` / `<CR>` on dir | 展开目录并跳到第一个子节点 |
| n (project log buf) | `h` on commit | 折叠 commit |
| n (project log buf) | `h` on child node | 折叠父节点 |
| n (project log buf) | `H` | 折叠当前 commit 并跳回 commit 行 |
| n (project log buf) | cursor on file | 自动显示该 commit 下该文件的 diff |
| n (project log buf) | `<CR>` on file | 手动刷新该文件 diff |
| n (log buf) | `d` | 切换 changes-only；single 模式压缩 diff 上下文，dual 模式折叠未变区域 |
| n (log buf) | `D` | 切换 single / dual diff 模式 |
| n (log buf) | `?` | 打开帮助浮窗并进入 help 窗口 |
| n (help buf) | `q` / `<Esc>` | 关闭帮助浮窗并返回 log 窗口 |
| n (log buf) | `<CR>` | 禁用；diff 由光标移动和 Visual 选择自动刷新 |

## 依赖

- 无外部插件依赖
- 需要 git 命令行工具

## 懒加载

通过 `ext-loader.lua` 注册，首次按 `<leader>gl` 或 `<leader>gL` 时加载。
