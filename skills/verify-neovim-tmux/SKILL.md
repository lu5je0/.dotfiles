---
name: verify-neovim-tmux
description: 通用 Neovim 配置修改验证。用隔离 tmux 启动完整配置，通过真实按键、屏幕捕获与运行状态验证快捷键、编辑模式、窗口、标签页、弹窗、高亮、自动命令和性能；适用于要求实测 Neovim、真实 TUI 验证或复现交互问题的任务，不绑定任何具体插件或功能，不以 headless 测试或内部函数调用替代用户入口。
---

# 用 tmux 验证 Neovim 配置

使用随附脚本完成机械操作。不要重新编写 tmux/RPC 控制器，不要用“代码看起来正确”代替运行证据。

## 不可省略的规则

1. 启动**正常 Neovim TUI 和待验证的完整配置**。不要用 `--headless`、`-u NONE`、`--embed` 替代。
2. 通过用户实际使用的按键或 Ex 命令进入功能。不要直接调用 `require('被测模块').某函数()`，不要用 `:doautocmd` 冒充真实输入事件。
3. 修改配置后启动新实例。不要清空 `package.loaded` 热重载后就声称新启动正常。
4. 每个结论必须有该实例的屏幕捕获；状态快照/计数只作辅助证据。`READY`、`INPUT_SENT`、文字匹配都不是最终 PASS。
5. 等待超时必须检查捕获并报告失败或阻塞。不要忽略退出码、扩大等待到无穷、手动刷新后冒充自动刷新。
6. 使用独立实例和一次性数据。不要给用户当前 Neovim/tmux 发送按键，不要在真实仓库执行 stage/reset/stash/delete 等验证操作。
7. 不运行测试套件或 typecheck 代替本 skill 的运行验证。可以读测试了解预期，再走真实界面。

## 1. 写出验证目标

先写三个简短条目，再启动：

- **入口**：用户按什么键或执行什么命令？从当前配置读取，不要猜 leader 或键位。
- **变化**：外部文件操作、编辑操作、焦点变化等，如何触发被修改的路径？
- **证据**：屏幕哪一行、标记、弹窗或光标会变化？至少再选一个边界场景。

先检查 `git status` 与相关 diff，保留用户未提交改动。阅读配置目录的 AGENTS.md。依赖缺失、配置启动报错时先报告环境阻塞，不要偷偷禁用插件或换成最小配置。

## 2. 启动隔离实例

依赖：Python 3.9+、tmux、具有 `vim.system` 的 Neovim。适用 macOS/Linux/WSL；Windows 原生终端不在此脚本覆盖范围。

以下 `SCRIPT`、`CONFIG`、`SESSION` 都是占位符，执行时必须替换成实际绝对路径：

- `SCRIPT`：本 SKILL.md 同目录的 `scripts/nvim_tui.py`。
- `CONFIG`：待验证的配置目录或 init.lua/init.vim；此 dotfiles 仓库使用 `vim/`。
- `SESSION`：`start` 输出的 `session` 字段，是**目录**，不是 RPC socket。

```bash
python3 SCRIPT start --config CONFIG --trace
```

读取输出，记录 `session`、`cwd`、`snapshot` 和启动捕获。后续每条工具命令都传入实际 SESSION；不要假定上一个 shell 的变量仍存在。

默认 cwd 是新建的空工作区。需要 Git、LSP 等项目条件时，在这个一次性工作区准备真实 fixture，然后通过按键重新进入功能；也可以先准备临时目录，再用 `--cwd /绝对/临时目录` 启动。不要使用真实仓库测试破坏性操作。

脚本会：

- 启动 UUID 命名的独立 tmux server，使用 `-f /dev/null`，不读取用户 tmux 配置。
- 在正常 PTY 中运行 Neovim，加载完整配置并补入 runtimepath；RPC 仅作控制通道。
- 使用 `-i NONE` 避免读写用户 ShaDa，将 Neovim 日志与屏幕证据保留在会话目录。
- 等待 RPC 和 UI 就绪，返回 `READY_NOT_VERIFIED`；这不保证插件已完成懒加载或功能正常。

**隔离不等于沙箱**：完整配置中的插件仍可能读写自己的缓存、访问剪贴板或启动外部服务；不要自动安装/更新插件，不要假定所有系统副作用都被隔离。

## 3. 输入真实按键并等界面

以下只演示控制器用法，**不是待修改功能的验收**；实际验证时替换成第 1 步确定的入口与结果：

```bash
python3 SCRIPT keys SESSION '<Esc>:enew<CR>iNVIM_TUI_BEFORE<Esc>'
python3 SCRIPT wait SESSION --text 'NVIM_TUI_BEFORE' --label before
python3 SCRIPT keys SESSION 'gg0ciwNVIM_TUI_AFTER<Esc>'
python3 SCRIPT wait SESSION --text 'NVIM_TUI_AFTER' --timeout 5 --label after
python3 SCRIPT wait SESSION --text 'NVIM_TUI_BEFORE' --absent --label old-text-gone
python3 SCRIPT capture SESSION --label final
```

- 支持 Neovim 按键记法：`<Esc>`、`<CR>`、`<C-n>`、`<Left>`。
- Ex 命令也通过输入进入，例如 `keys SESSION '<Esc>:edit sample.txt<CR>'`。
- 字面 `<` 使用 `<lt>`；正常模式、插入模式、终端模式不能混为一谈，不确定时先 `inspect`。
- 在一次会话内按顺序执行操作；不要并行发按键、切窗口、捕获或关闭。
- 选择能唯一标识结果的文字。文件名可能同时出现在 tabline、状态栏和编辑窗口中，必须确认它出现在目标区域。

`wait` 在成功和超时时都保存屏幕；超时返回非零。读取 `capture.screen` 和保存的文本，确认文字出现在正确窗口，且前后变化符合预期。不要仅看退出码。

## 4. 按变更类型选择场景

不要为每次修改机械执行全部场景；选择能经过被修改路径的一条主流程和至少一个边界。

| 变更类型 | 从真实入口触发 | 观察证据与边界 |
|---|---|---|
| 快捷键、懒加载 | 在正确模式输入实际 LHS，检查首次与再次触发 | 捕获预期动作/弹窗，检查是否误触原生键或需要重复按键 |
| 编辑、文本对象、多光标 | 准备用例文本，实际进入 normal/insert/visual 模式编辑 | 比较文本、光标与选区；检查 undo、Esc 和重复操作 |
| 窗口、标签页、浮窗 | 通过命令或映射打开、切换、关闭 | 捕获布局、焦点与恢复位置；检查第二次打开及关闭后残留 |
| 渲染、折叠、高亮 | 打开代表性文件，实际移动、折叠或切换主题 | 保存 plain/ANSI；像素或字体问题另取终端客户端截图 |
| 自动命令、外部同步 | 实际保存/重读文件、切 buffer/tabpage，或注入终端焦点报告 | 捕获事件前后变化；检查不相关事件不应触发的行为 |
| 后台工作、性能 | 完成正常启动后保持空闲，再触发相关操作 | 比较调用数与 changedtick；不要预设所有配置都必须零调用 |

### 可选：焦点事件

```bash
python3 SCRIPT focus SESSION lost
# 如场景需要，此时对一次性 fixture 做外部修改。
python3 SCRIPT capture SESSION --label before-focus
python3 SCRIPT focus SESSION gained
python3 SCRIPT capture SESSION --label after-focus
```

`focus` 向 PTY 输入终端标准报告 `ESC [ O` / `ESC [ I`，由 Neovim 解析并触发 FocusLost/FocusGained；不是直接调用 autocmd。异步结果另用 `wait` 等到预定判据，不能把紧接着截到的旧画面当最终结果。

### 可选：运行状态与开销

```bash
python3 SCRIPT inspect SESSION --seconds 5
```

`inspect` 返回 UI 数量、当前模式/光标、窗口与标签页 ID、已加载 buffer 的 changedtick、版本、消息与错误信息。启用 `start --trace` 后，还返回 `trace.system_calls`、`focus_gained`、`focus_lost`。UI 数量不是窗口数；窗口 API 可能包含内部消息/命令窗口，不要仅凭列表长度断言可见布局。

`inspect --seconds 5` 在不注入按键的情况下持续观察，保存前后快照与屏幕。比较**增量**，不要把初始化所需的进程启动算成空闲工作；结合配置预期解释外部事件造成的变化。

探针只包装 `vim.system`，不伪造结果，也不统计 `vim.fn.system`、`jobstart` 等其他调用方式；计数范围是该实例，不是某个插件。若验证性能本身，说明探针的观测开销，不要用这套控制器的耗时推导精确延迟。

## 5. 检查边界并清理

根据改动选至少一个边界：再次操作、关闭重开、切 tabpage 再返回、删除当前项、快速连续按键、Esc 取消，或“没有变化时不应刷新”。

完成后先保留最终捕获与消息，再关闭：

```bash
python3 SCRIPT inspect SESSION
python3 SCRIPT stop SESSION
```

`stop` 只关闭此会话自己的 Neovim/tmux session，使用 `qa!` 放弃该验证实例的未保存编辑；卡住时仅结束这个命名 session。所有 fixture、日志、快照、plain/ANSI 捕获保留在 SESSION 内。

不要用无 `-L` 的 tmux 命令清理，不要 `pkill nvim` / `killall tmux`，不要删除用户数据；不要用 `rm -rf` 清掉唯一证据。

## 6. 如实报告

使用这个简短模板；没有证据的项目不要填 PASS：

```text
结论：PASS / FAIL / BLOCKED
实例：正常 Neovim + 完整配置，隔离 tmux，配置路径与版本
操作与观察：实际按键/外部变化 → 屏幕变化；附捕获路径
边界：至少一个额外操作 → 观察结果
开销：若检查刷新，给前后调用计数与观察时长
未覆盖：桌面焦点转发、实际字体渲染、其他平台等
清理：实例已关闭，证据目录保留
```

必须区分两类边界：

- **终端焦点报告注入 ≠ 实际桌面焦点切换**。本脚本不能证明用户的 kitty/iTerm/tmux 链路真的会转发焦点报告；需要用户现场或桌面操作另外验证。
- **字符网格/ANSI ≠ 桌面像素截图**。plain 捕获能证明文字和字符布局，ANSI 还能保留发出的颜色/属性；字体、实际像素颜色等问题需要真实终端客户端截图，不能把捕获文本伪装成截图。

若遇阻塞，保留现场并说明卡在依赖、配置启动、按键入口、焦点转发还是界面判据。不要用 headless 通过来掩盖 TUI 未验证。
