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
- `common/commit-selection.lua`: 项目日志与行历史共用的 commit 勾选、标记与计数；以稳定 commit key 保存选择，buffer 内容变化后重新挂载行首 `✓` inline extmark
- `common/selected-diff.lua`: 新 tab 中查看所选提交的净变化；左侧使用 `common/selected-diff-ui.lua` 和 common tree，右侧 single / dual 显示当前文件的合并结果，统一管理异步读取、临时资源清理、取消和切换
- `common/net-diff.lua`: 合并所选改动；项目日志使用临时 bare repo 和独立 index，以源仓库对象库为 alternate，连续提交直接读取结果树，离散提交按 first-parent patch 做三方应用；行历史对追踪块做三方合并。真实工作区、暂存区、refs 与对象库均不写入，冲突时明确报错
- `line-log/`: 行级 git log 子模块
  - `init.lua`: Neovim 入口，负责 session、窗口、buffer、prefetch 调度与 UI 驱动
  - `core.lua`: 纯算法与 git 历史收集核心，负责 revision/path 链、tracker 初始化与 block 推进；测试与运行时共用
  - `blob-store.lua`: 批量加载并缓存 `rev:file` 内容，供测试与运行时共用
  - `block.lua`: Block 类与 diff 生成（纯算法，不依赖 state）
  - `ui.lua`: 窗口、buffer、statusline、高亮、keymaps；直接消费 `state.tracker`
- `common/selected-diff-ui.lua`: 行历史与 History 的净变化视图共用的提交 / 文件树渲染，由 `common/selected-diff.lua` 使用
- 项目历史由 `../sidebar/sources/history/` 提供：`init.lua` 为 source / open 入口，`model.lua` 管理异步任务，`core.lua` 解析 Git 输出，`tig.lua` 提供提交图算法；本模块只注册快捷键与 blame 跳转。

## 功能说明

### Line Log (`<leader>gl` visual 模式)

1. Visual 模式选中代码行后按 `<leader>gl`
2. 底部 split 窗口显示影响选中行的 commit 列表
3. 异步逐版本加载，窗口名称显示加载进度
4. 在 log 窗口移动光标会自动在右侧 vsplit 预览当前 commit 对选中行的 diff
5. 在 log 窗口 Visual 选中多个 commit 会自动显示连续范围的聚合 diff；Visual 模式按 `<CR>` 在新 tab 合并选区内改动，按文件查看净变化，合并冲突时提示

### Project Log (`<leader>gl` normal 模式)

1. 普通模式 `<leader>gl` 打开 Sidebar History，提交树使用与 Changes 相同的渲染、缩进、展开箭头、文件图标和状态颜色。提交行显示短 hash 与标题，`K` 查看 hash、作者、时间与完整标题。
2. commit 默认折叠，目录默认展开，连续目录链合并显示；打开目录时沿唯一子目录自动展开到分支、文件或空目录；收起时整条合并显示的目录链一起关闭，分支以下子节点及 commit 重开时保留折叠状态；`h/l`、`zo/zc` 折叠/展开，文件行 Enter 打开工作区文件。
3. Merge 提交展开后按所有 parent 分组（暖黄色标题），每组比较该 parent 与 merge 最终快照；合并时的手动改动按实际差异出现在一组或多组，不单独推断冲突解决。文件列表首次展开时异步加载并缓存，无变化显示 `No changes`；切页/关闭取消任务，返回后恢复未完成查询。各组目录折叠状态独立，jump-to-file 等待分组加载后定位。
4. 提交行 Space 预览 hash、作者、时间、标题和变更文件列表（含 rename 路径）；再按进入浮窗，`q` / Esc 关闭。文件行 Space 使用共享浮窗预览该提交相对 parent 的变化（普通提交取 first parent，merge 取所属分组），再按进入预览；移动光标关闭预览。root commit 与空树比较，rename 使用旧路径。
5. `d` / `c` 与 Changes 共用布局、changes-only 偏好，预览内切换复用加载结果。预览关闭、切页和切 Neovim tab 后，过期回调不得重开窗口。
6. `m` 勾选提交（支持 Visual 批量），`U` 清空；有勾选时 Enter 或 Visual Enter 在新 tab 查看净变化。
7. `r` 刷新，`ga` 加载全部，`Z` 切换 Sidebar 宽度；Visual `<leader>gl` 与 `<leader>gL` 保留独立的行/文件历史窗口。
8. `gG` 在普通列表与 Tig 提交关系图之间切换；每个提交一行，保留文件树、光标和勾选。图形按已加载提交生成并缓存，刷新历史后失效，不在 render / CursorMoved 中计算。
9. History 状态按 Neovim tabpage 隔离，切页/关闭取消加载并保留已完成的历史、展开和勾选；`model.lua` 只产出数据，Sidebar source 管理树、按键和预览目标。

### 离散 commit 勾选（两个日志窗口共用）

- History 用 `m`、行历史用 `<Space>` 勾选/取消光标所在 commit；History 子节点按所属 commit 处理
- Visual 模式沿用各入口的勾选键批量处理范围内 commit；范围已全部勾选时批量取消，保留 Visual 选区
- 勾选行首显示 `✓`，日志 statusline 显示已选数量；`U` 清空勾选
- Normal 模式 `<CR>` 在新 tab 打开所有已勾选 commit 的文件树；Visual Enter 在两个日志窗口均打开当前选区内 commit 的文件树
- 按日志中的历史顺序（从旧到新）尝试合并改动；连续提交比较最早提交的父树与最终结果树，先改后还原、新增后删除的文件从树中消失；root commit 基于空树，merge 取 first parent
- 离散选择仅应用所选提交的改动，在临时 index 中做三方合并，不混入跳过的提交；缺少依赖或冲突时只提示错误，不展示不完整结果，也不悄悄退回逐条 diff
- 项目日志只展示已提交历史及其变更文件，未提交改动由 Sidebar Changes 展示；行历史只展示原追踪代码块
- 新 tab 中 `c` 切换 changes-only，`d` 切换 single / dual，切换布局保留上下文偏好；`]f` / `[f` 切换净变化文件；`q` 关闭并返回原日志，保留勾选。dual 的 `]c` / `[c` 保留 Neovim 原生 diff hunk 跳转
- 左侧将所选 commit 的变更文件按完整路径合并为一棵树，同一路径只显示一次，不同目录下的同名文件各自保留；树根显示所选提交总数。目录默认展开，复用项目日志的图标、高亮、连续目录链压缩和 `l` / `<CR>` / `h` / `H` 展开折叠操作；文件行移动光标即可更新右侧预览，`<CR>` 强制刷新
- 右侧 single 显示当前文件的一份净变化 unified patch，dual 并排显示合并前/后的内容；两种模式均保留左侧文件树。合并后完全无变化时显示 `No net changes`，不创建 diff 窗口；关闭、失败时清理临时数据，切换文件时取消过期读取

### Changes (`<leader>gs`)

Git Changes tab 现由 `lua/lu5je0/ext/sidebar/` 提供（本模块不再包含 git-status 窗口）。`<leader>gs` 打开/定位 sidebar 的 Git Changes tab，顶部 `Changes` 章节列出当前仓库所有受影响的文件（合并 staged / unstaged / untracked，每个路径只出现一次）。

1. 每个 tabpage 首次进入 Git Changes 时光标定位到第一个变更文件；之后同 tabpage 再按仍定位当前文件。
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
   - Show in project log（调用 `require('lu5je0.ext.sidebar.sources.history').open({ jump_to_sha = sha, jump_to_file = abs_path })`，自动滚动到对应 commit 并定位文件行）
3. 菜单期间隐藏光标，避免出现下划线/闪烁；关闭后恢复
4. 被点中的源 buffer 行 blame 高亮为 `GitBlameSelected`，菜单关闭后清除
5. blame 还未加载会先提示 `Loading blame...`，未提交行（`00000000`）提示 `Line is uncommitted`

### Project Log 跳转入口

`require('lu5je0.ext.sidebar.sources.history').open(opts)` 支持以下可选参数：

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
- 行历史在 `BufWipeout` 停止进程；项目历史由 Sidebar 生命周期取消任务，共享 diff_preview 用 generation 防止过期结果重开窗口
- commit 列表格式：`%h %ad %s`，日期精确到秒
- 高亮：commit hash 用 `Number`，日期用 `Comment`

### 测试约定

- `vim/tests/line-log/spec.lua` 负责 line-log 算法测试，当前同时覆盖：
  - 现有 dotfiles 仓库里的固定 commit/文件/行段 case
  - 运行时动态创建的临时 git 仓库 fixture
- `vim/tests/project-log/spec.lua` 负责 project-log graph 渲染回归测试，覆盖复杂 merge / crossover 历史段，并使用 `tig-fixtures.json` 中由 Tig 2.6.0 官方 graph-v2.c 生成的 golden cells 校验 UTF-8 图形与颜色编号
- `vim/tests/git-selection/spec.lua` 通过真实按键覆盖 History 的 Sidebar 布局、切页/关闭恢复、per-tab 隔离及两个日志入口的 `c` / `d` 独立切换、dual 的 changes-only 折叠与 `D` 映射移除、Space / m 勾选、Visual Enter、文件树折叠/展开/自动预览、single / dual 净 diff、离散提交合并成功/冲突、先改后还原与新增后删除、rename/delete、未提交改动与 History 隔离、真实 index/工作区不变、临时资源清理，以及一加 6 的四提交 `gnome.nix` 净变化为空的真实 case
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
| x (line log buf) | Visual 选择 | 自动预览选中 commit 范围的聚合 diff |
| n / x (line log) / (History) | `<Space>` / `m` | 切换当前 commit / 批量勾选选区内 commit |
| n / x (log buf) | `U` | 清空所有 commit 勾选 |
| n (log buf, 有勾选) | `<CR>` | 新 tab 打开已勾选提交的文件树 |
| x (log buf) | `<CR>` | 新 tab 打开当前选区内提交的文件树 |
| n (project log buf) | `l` / `<CR>` on commit | 展开 commit 文件树，光标停留当前提交，保留子目录折叠状态 |
| n (project log buf) | `l` / `<CR>` on dir | 展开目录并跳到第一个可见子节点，保留后代折叠状态 |
| n (project log buf) | `h` on commit | 折叠 commit |
| n (project log buf) | `h` on child node | 折叠父节点 |
| n (History) | `<Space>` | 打开历史 diff 预览，再按进入浮窗 |
| n (History) | `K` | 查看完整提交信息 |
| n (History) | `gG` | 切换 Tig 提交关系图 |
| n (History) | `<CR>` on file | 打开工作区文件；有勾选时查看所选净变化 |
| n (log buf) | `c` | 切换 changes-only；single 压缩上下文，dual 折叠未变化区域 |
| n (log buf) | `d` | 切换 single / dual，保留 changes-only 状态 |
| n (log buf) | `?` | 打开帮助浮窗并进入 help 窗口 |
| n (help buf) | `q` / `<Esc>` | 关闭帮助浮窗并返回 log 窗口 |
| n (line log buf, 无勾选) | `<CR>` | 不操作；diff 由光标移动和 Visual 选择自动刷新 |
| n (selected diff tree) | `l` / `<CR>` / `h` / `H` | 展开节点 / 刷新文件预览 / 折叠父节点 / 折叠整棵合并树 |
| n (selected diff tab) | `c` / `d` | 独立切换 changes-only / single 与 dual 布局 |
| n (selected diff tab, dual) | `]c` / `[c` | Neovim 原生下一处 / 上一处 diff hunk |
| n (selected diff tab) | `]f` / `[f` | 下一个 / 上一个文件 |
| n (selected diff tab) | `q` | 关闭汇总 tab，返回原日志 |

## 依赖

- 无外部插件依赖
- 需要 git 命令行工具
- `lua/lu5je0/ext/statuscol.lua` 在自定义 segment 中渲染 blame 并把右键事件路由到 blame 模块；本模块不反向依赖 statuscol
- History、Changes 和 line-log 的窗口均使用全行 cursorline，与 NvimTree 一致

## 懒加载

通过 `ext-loader.lua` 注册，首次按 `<leader>gl` / `<leader>gL` / `<leader>gb`，或执行 `:GitStatusLog` 时加载。
