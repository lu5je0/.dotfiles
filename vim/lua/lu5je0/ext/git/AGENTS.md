# Git 模块工作指引

## 模块职责

提供 git 相关的增强功能，当前主要实现 line log、项目级 commit log 查看，以及 statuscolumn 内嵌的 git blame 显示与右键菜单。

## 目录结构

- `init.lua`: 模块入口，注册按键映射与 git 相关用户命令
- `blame/`: statuscolumn 内嵌 git blame 子模块（不依赖 gitsigns）
  - `init.lua`: 入口与生命周期；`<leader>gb` 切换、`WinScrolled` / `BufDelete` autocmd、`nvim_buf_attach`；`M.on_click` 路由 statuscol 右键
  - `porcelain.lua`: 解析 `git blame --porcelain` 输出为 `line_to_sha` 与 `commits` 表
  - `git.lua`: 用 `vim.system` 异步跑 `git blame --porcelain --contents -`；同 buffer 并发请求合并到一个进程，所有排队回调都会触发
  - `cache.lua`: 每 buffer 缓存 `tick / line_to_sha / commits`；commit 包含稳定调色板色与预格式化文本，编辑时按 `on_lines` 平移 `line_to_sha`
  - `selection.lua`: 被右键选中的行状态
  - `render.lua`: statuscolumn segment 函数与 redraw 工具
  - `colors.lua`: 定义 `GitBlame1`–`GitBlame5` 与 `GitBlameSelected`，并响应 `ColorScheme` 重新挂载
- `blame-menu.lua`: blame 区域右键菜单；提供 copy hash / show commit / show in project log 动作，被点中的源 buffer 行 blame 高亮为 `GitBlameSelected`，菜单关闭后清除
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

### Changes (`<leader>gs` 顶部章节)

1. `<leader>gs` 打开 git status 窗口时，顶部新增 `Changes` 章节，列出当前仓库所有受影响的文件（合并 staged / unstaged / untracked，每个路径只出现一次）
2. 每个文件名末尾显示 git porcelain 的 2 字符状态：
   - `MM` 同时有 staged 改动和 unstaged 改动
   - ` M` / `M ` 仅 unstaged 或仅 staged 修改
   - `A `, ` D`, `R `, `??` 等照常透出
3. Changes 是预览定位入口；光标移到文件行时右侧 vsplit 自动按 file 的 XY 派发到正确的 diff 后端（worktree / index / HEAD）
4. 该章节有意不支持批量 stage/discard（`A` / `X`），避免 `MM` 这类混合状态被歧义批处理；逐文件的 `a`（stage）和 `x`（discard）仍然可用，会按 file 的 XY 派发到 untracked / unstaged / staged 分支
5. statusline 总数以 Changes 章节计算，避免 `MM` 文件被双重计数

### Blame Menu (statuscolumn 右键)

1. blame 区域右键弹出原生 popup 菜单，菜单出现在鼠标位置，空间不够时由 nvim 自行翻转
2. 菜单项：
   - Copy commit hash（完整 SHA → `+` / `"` 寄存器）
   - Show commit（`git show --stat --patch <sha>` 渲染到新 tab）
   - Show in project log（调用 `project_log.show({ jump_to_sha = sha, jump_to_file = abs_path })`，自动滚动到对应 commit 并定位文件行）
3. 菜单期间隐藏光标，避免出现下划线/闪烁；关闭后恢复
4. 被点中的源 buffer 行 blame 高亮为 `GitBlameSelected`，菜单关闭后清除
5. blame 还未加载会先提示 `Loading blame...`，未提交行（`00000000`）提示 `Line is uncommitted`

### Project Log 跳转入口

`project_log.show(opts)` 支持以下可选参数：

- `jump_to_sha`：commit 列表渲染完成后把光标定位到匹配 hash（精确或前缀匹配）的 commit 行
- `jump_to_file`：可与 `jump_to_sha` 组合；定位到 commit 后自动展开其文件树，并把光标停在匹配路径的文件行上。匹配同时考虑 `file.path` 和 `file.old_path`，rename commit 也能命中
- 传 `jump_to_sha` 时不再无脑全量加载，会按目标距 HEAD 的距离动态选择 `commit_limit`
- 加载完仍未命中目标 sha 时会 notify 警告
- 不传任何 opts 时与 `<leader>gl` 原行为一致

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
| n (source buf) | `<leader>gb` | 切换 statuscolumn 内嵌 git blame |
| any (statuscolumn) | 右键 on blame 区域 | 弹出 blame 操作菜单，被点行高亮 `GitBlameSelected` |
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
- `lua/lu5je0/ext/statuscol.lua` 在自定义 segment 中渲染 blame 并把右键事件路由到 blame 模块；本模块不反向依赖 statuscol
- `project-log` / `git-status` / `line-log` 的窗口均使用全行 cursorline，与 NvimTree 一致

## 懒加载

通过 `ext-loader.lua` 注册，首次按 `<leader>gl` / `<leader>gL` / `<leader>gs` / `<leader>gb`，或执行 `:GitStatusLog` 时加载。
