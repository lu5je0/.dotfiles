# pi 配置

pi（coding agent）的用户级配置目录：`~/.pi/agent/`。本目录由 `scripts/setup.d/modules/unix/pi.sh` 部署。

## 部署方式

- 子目录（如 `extensions/`）→ symlink 到 `~/.pi/agent/<name>`（整目录链接，实时生效）
- `models.json` → symlink（pi 只读它，不写）
- `simple-perm.json` → symlink（`simple-perm` 扩展只读它，不写）
- `keybindings.json` → symlink（pi 只在迁移旧式键位 id 时才回写，本文件全是新式 id；里面三条都是为了 `thinking-fold` 占 ctrl+t，别删，原因见下面）
- `settings.json` → **合并**而非链接，因为该文件 pi 会自己写入运行时键

## settings.json 的所有权划分

`~/.pi/agent/settings.json` 由 dotfiles 与 pi 共同持有：

- **dotfiles 管理**（本目录 `settings.json` 中出现的键，dotfiles 值优先）：
  - `editorPaddingX` — 输入框边距
  - `packages` — 声明的插件清单，**整体替换**，是插件集合的唯一真相来源
- **pi 管理**（不在本目录声明，保留 pi 写入的值）：
  - `lastChangelogVersion`、`theme`、`defaultProvider`、`defaultModel` 等

新增受管键时，直接加到 `pi/settings.json`；setup 时会把该键覆盖进 live settings。
不要把只想在本机改的运行时键（如 `defaultModel`）写进来，否则会被 dotfiles 固定。

## 插件（pi packages）管理

pi 的"插件"是 npm/git 包，通过 `packages` 数组声明，包体装在 `~/.pi/agent/npm/node_modules/`。

- 声明：在 `pi/settings.json` 的 `packages` 里加 `npm:<pkg>` / `git:<host>/<path>@<ref>` / 绝对路径
- 安装：`pi.sh` 会检测缺失的 npm 包并执行 `pi install npm:<pkg>`；pi 启动时也会自动装缺失项
- 升级：`pi update --extensions`（或 `pi update --all`）
- 移除：从 `pi/settings.json` 删掉条目，setup 后 pi 不再加载；包体可手动 `npm rm` 清理

当前插件：

- `npm:pi-commandcode-provider` — commandcode provider
- `npm:pi-smart-web-search` — web_search 工具
- `npm:pi-smart-fetch` — web_fetch 工具
- `npm:@juicesharp/rpiv-ask-user-question` — ask_user_question 工具
- `npm:pi-background-tasks` — bg_run / bg_delegate / fusion 等后台任务（本地行为调整见下节）

## bg 任务（bg-tweaks）

`extensions/bg-tweaks.ts` 只针对 `pi-background-tasks`，不 fork 上游包：

- **关掉插件自己的版本检查**：插件在 `session_start` 查一次 npm latest，命中就往 footer 的
  bg 片段塞 `↑ vX.Y.Z /bg-update`，更新频繁时很吵。官方开关是 `PI_BG_DISABLE_UPDATE_CHECK=1`，
  由本扩展在加载期写进 `process.env`，不往 shell 环境塞 pi 专属变量。时序成立是因为 pi 先加载
  本地扩展目录、后加载 `settings.packages` 的包，而插件到 `session_start` 才读这个变量；
  已显式设过就不覆盖（`PI_BG_DISABLE_UPDATE_CHECK=0` 可临时打开）。
  注意这是**插件**的检查；pi 主体自己的版本检查是另一个开关（`PI_SKIP_VERSION_CHECK`），
  而 pi 的 `Package Updates Available` 块只看包是否 pinned，本扩展管不到。
- **终态后自动 `/bg-clear`**：插件的 `bg N done · /bg-clear` 只有打开任务详情或手动 `/bg-clear`
  才消。扩展订阅插件的 EventBus 终态频道 `pi-background-tasks:terminal:v1`，最后一次终态之后
  静默 10 秒（可用 `PI_BG_AUTO_CLEAR_DELAY_MS` 改，非法值回落默认）补发一次 `/bg-clear`。
  发送走 `pi.sendUserMessage("/bg-clear", { expandPromptTemplates: true })`：pi 的 `prompt()` 对
  `/` 开头的扩展命令是「立即执行、不落消息、不触发 turn」的分支，流式期间也可用，语义等于
  手动敲一次（会闪一行短暂的 `Cleared N ...` 状态）。先查 `pi.getCommands()` 确认命令在，
  否则不加 `expandPromptTemplates` 的普通提示词会变成给模型的一句话。多个任务连续结束共用
  一个 debounce；按 `task.id` 去重（终态帧可能重发）。
- 测试：`node pi/tests/bg-tweaks-smoke.mjs`（延迟解析 + 开关 + 去重/debounce/畸形帧/shutdown，
  零依赖，直接 import `.ts`——扩展只有 `import type`，不需要 bash-timeout 那套包发现沙盒）

## 权限（simple-perm 扩展）

`extensions/simple-perm.ts` 是自写的三模式权限扩展，零依赖，沙箱后端按平台选：Linux 要 PATH 里有 `bwrap`，macOS 用系统自带的 `/usr/bin/sandbox-exec`：

| 模式 | 项目外读 | 项目外写 | bash |
|---|---|---|---|
| `ro`（默认） | 允许 | 拒绝 | 沙箱，项目+白名单+/tmp 可写 |
| `ask` | 允许 | 弹确认（可记住目录） | 同上 |
| `yolo` | 允许 | 允许 | 不沙箱 |

- 切换：`ctrl+y` 循环、`/perm <ro|ask|yolo|clear>`、启动 `--perm <mode>`、`PI_PERMISSION_MODE` 环境变量
- 模式会记住：切换时写 session entry（resume/`/reload` 生效）+ `~/.pi/agent/simple-perm-state.json`（下次启动生效）。启动优先级：`--perm` > 本 session 记录 > `PI_PERMISSION_MODE` > 状态文件 > 默认 `ro`
- 白名单：`simple-perm.json` 的 `allowWrite`（本目录），项目级可加 `.pi/simple-perm.json` 追加；列在这里的目录读写全放行，`/tmp` 恒可写
- 沙箱实现是 `tool_call` 里把 bash / bg_run 命令改写成（`ro`、`ask` 都走这条）：
  - Linux：`bwrap --ro-bind / / --bind <项目> … -- /bin/sh -c '<原命令>'`
  - macOS：`sandbox-exec -p '<Seatbelt profile>' /bin/sh -c 'cd <项目> && <原命令>'`，profile 是 `(allow default)` + `(deny file-write*)` + 按白名单 `(allow file-write* (subpath …))`（Seatbelt 后匹配的规则覆盖前面的）
  - 两者语义一致：整个文件系统只读，只有项目 + 白名单 + /tmp 可写；沙箱里再套多少层 shell 都出不去
  - 后端探测失败（Linux 无 bwrap、macOS 的 sandbox-exec 跑不通）时不静默放行，改为逐条确认；无 UI 时直接拒绝
  - 因此只读区域里需要写 HOME 缓存的工具（npm/uv/cargo → `~/.cache`、`~/.npm`、`~/.cargo`、macOS 的 `~/Library/Caches`）会失败，需要就写进 `allowWrite`；`/tmp` 已内置
- 项目本身在 `/tmp` 下时，`../x` 这类相对路径仍可写（`/tmp` 整个可写）
- macOS 特有：`TMPDIR`（`/var/folders/…/T`，0700）和 `/tmp` 一样被当作平台自带可写，否则 mktemp / python tempfile / node os.tmpdir 全 EPERM；Seatbelt 按**解析后的真实路径**匹配，所以 `/tmp` 实际写成 `/private/tmp`，profile 里的路径都过 `canonicalize()`
- macOS 与 bwrap 的已知差异（不影响边界强度）：没有 bind mount（ask 模式放行=加进 profile 允许列表，语义反而更准）；unlink 已放行的单个文件也能成功（bwrap 下要父目录可写）；没有 `--die-with-parent`，pi 被 kill 后子进程不会被连带收走
- `sandbox-exec` 被 Apple 标了 deprecated，但 Darwin 25（macOS 26）实测仍可用；将来真跑不通时探测会失败并自动退回逐条确认
- Linux 上 bwrap 只映射当前 uid，root 拥有的文件在沙箱内显示成 `nobody`，于是 ssh 会因 `/etc/ssh/ssh_config` 的属主校验挂掉（`git push` exit 128）；扩展把 `~/.ssh` 盖到 `/etc/ssh` 上规避。这层 hack 只对 bwrap 生效，macOS 不需要
- 覆盖范围：`bash` 工具 + `bg_run`（同类工具名可加在 `simple-perm.json` 的 `commandTools` 里）；`!` 用户 bash 和第三方扩展自己 spawn 的进程不走这条路径，不受沙箱约束
- ask 模式下会启发式扫 bash/bg_run 命令里的项目外写入目标（重定向、rm/mv/cp 等写类命令的参数、`sh -c` 内嵌脚本递归），命中就弹窗；允许后**不是关沙箱**，而是只把那几个目录/文件额外放行（unlink/rename 需要父目录可写，所以只有纯内容写才绑文件本身）
  - heredoc 正文不扫（`cat > x.js <<'EOF' … EOF` 里 `=> "/Users/me"` 这类正文不是 shell 代码）。未闭合的 heredoc 一律不动；`bash <<EOF` 这种真把正文当脚本跑的会漏判，由沙箱在内核层兜底
  - 放行目标是「最近存在的祖先目录」：`mkdir -p ~/新目录/x` 里的目录还不存在，以前算不出目标→不弹窗也不成功，只能 EPERM
  - 弹窗用 `ctx.ui.custom()` + `overlay`（bottom-center、宽度铺满，见 `PermDialog`），**不要用 `ui.select()`**：后者的标题不是弹层，而是直接替换输入框画在 editor 区域、没有滚动条，命令一长整个 dock 超过终端高度、editor 区域被压扁（fullscreen 下 shrink 到 minSize 3），选项就跑到屏幕外（踩过）。overlay 有自己的定位/尺寸，弹窗里每行都在 `render(width)` 里按真实宽度截断，颜色自己分配（标题 accent、命令 dim、放行目标 muted），选项用 pi 的 `SelectList` + 1-4 直选。非 TUI（RPC）回退到 `ui.select`，文案同样先压短
- 写入边界会注入系统提示：`before_agent_start` 里往 `systemPromptOptions.sections.write_boundaries` 写一行事实披露，如 `simple-perm ro：可写 ~/Test、/tmp、~/.dotfiles；其余路径只读。`（section 名固定，pi 按 tag 增量替换）。可写目录由 `writableDirs(cwd, allowWrite)` 现算；`ask` 模式句尾加「写到边界外会弹窗确认」，`yolo` 直接 `delete` 这一节。只陈述事实，不写指令。注意 section 名只接受 `^[a-z][a-z0-9_-]*$`，内容为空就等于删掉

## 命令超时（bash-timeout）

`extensions/bash-timeout.ts` 在 `tool_call` 里给内置 `bash` 补 `timeout`，只改这一个字段，命令行
本身不碰，pi 原生 bash 渲染器（`$ cmd` + Took X.Xs）原样保留。起因：pi 的 bash schema 把 `timeout`
定义成可选（描述就写着 "optional, no default timeout"），模型漏传时一条不会自己结束的命令会永远
不返回。实测翻车是一条 `cmd | tail -40`：`tail` 等管道写端 EOF，而写端被漏掉的孙子进程
（`nvim --embed`、`script` 起的 pty）持有，外层 shell 也就不退出，agent 卡了 50 分钟。pi 自己的
超时路径会 `killProcessTree` 干掉整棵进程树，所以补上 `timeout` 就够了。

- 选档在 `lib/bash-timeout.ts`（零依赖纯函数，放 lib/ 是为了能脱开 pi 跑测试）：
  short 60s（交互式/常驻）→ long 1800s（构建/安装/测试/大网络动作）→ default 60s。
  先判 short，所以 `npm run dev` 走 60 而不是命中「npm ... run」的 1800。
  default 与 short 目前同值，等价于「非构建类一律 60 秒」，要更短就调 shortSeconds
- 模型显式传的合法 timeout 只做上界 clamp（默认 21600s）：`timeout: 86400` 等于没设，不能让它
  绕过兜底；传 0/负数/NaN（pi 会直接报 Invalid timeout）由扩展换成选档结果
- 配置（可选、只读、不创建）：`~/.pi/agent/bash-timeout.json`，字段与默认值见 `DEFAULT_CONFIG`；
  `PI_BASH_TIMEOUT` 环境变量只覆盖 defaultSeconds。非法项只 notify，安全默认照旧生效，
  绝不因为配置写错就让扩展失效
- 两张 patterns 表的误判方向不对称：`shortPatterns` 误判 = 把正常命令提前杀掉（危险，只收
  「几乎不可能自己退出」的形态）；`longPatterns` 误判 = 只是挂久一点（安全，可以放宽）。
  加模式时按这个标准，别反过来
- regex **不要带 `g` 标志**：`RegExp` 有 lastIndex 状态，带 g 时连续 `.test()` 会漏判
- 边界：只管 `bash`。`bg_run` 故意不动（异步 + 有任务面板 + 可手动 kill，塞默认超时反而会
  误杀 legit 的长编译）；用户自己敲的 `!` 命令也不管（人在等，随时 ctrl+c）
- `before_agent_start` 往 `systemPromptOptions.sections.bash_timeout` 写一行事实（各档秒数 +
  上界），让模型知道超长任务要显式传 timeout 或改用 bg_run；只陈述事实，不写「不要重试」那类指令
- **不往 footer 放东西**：曾经注册过一个 `cmd 300s` 的 chip，按用户要求去掉了（`footer-host.ts` 收的那些 chip 只留简单/权限/tps 这类常用信息）
- 测试：`node pi/tests/bash-timeout-pick.mjs`（52 条命令的选档 + 幂等 + 配置解析/clamp，零依赖）、
  `node pi/tests/bash-timeout-smoke.mjs`（真 SDK 载入扩展，验注入/clamp/非 bash 工具不受影响/
  prompt 段/不注册 footer chip）。两个脚本的包发现方式同 thinking-fold（从 `pi` 可执行文件往上找，
  **深 6**——pi-tui 藏在 `<pi-coding-agent>/node_modules/@earendil-works/pi-tui`，比安装根低 5 层）

## thinking 折叠（thinking-fold）

`extensions/thinking-fold.ts`：`**Thinking**` 标题 + 每行 `│ ` 侧栏；折叠时只留头 2 行 +
`… +N rows (ctrl+t)` + 尾 3 行（≤5 行不截）。

- **先渲染再切片，绝不自己折行**：thinking markdown 交给真 pi-tui `Markdown` 渲染成屏幕行
  （`renderPreviewRows`），然后只做两件事——切头尾、逐行包成行内代码（`literalRow`）。
  漂移的根源是「源文本宽度 ≠ 渲染后宽度」（行内标记被吃掉、列表续行被缩进、代码块加边距），
  自己算就永远差一点：旧版为此写了 589 行（行内标记宽度模型 + 列表缩进 + 围栏状态 + 尾巴重折 +
  硬换行），6 次提交全在修同一类高度漂移仍补不完。**这是本插件唯一的设计约束。**
- **行内代码是 ANSI 载体**：切片后的行会被 pi 重新解析一遍，而它们可能是围栏内部的行
  （`# 注释` 被认成标题并多补一行空行、` ``` ` 被认成新代码块、连续空行被吞）。包成 code span
  后外层不再解析、不增行、不吞空白，里面已渲染的 ANSI 原样保留。定界符取行内最长反引号串 +1，
  两侧各留一格空格（CommonMark 会吃掉这对空格）。
- **围栏标记行不占行**：预览渲染时把 `codeBlockBorder` 换成哨兵串（`\x1b[999m`，非法 SGR，
  终端忽略），渲染后按哨兵过滤整行。`codeBlockBorder` 在 pi-tui 里只在围栏开/闭两处调用
  （`dist/components/markdown.js`），所以过滤掉的恰好是那两行。同一主题里还要
  `codeBlockIndent: ""` + `highlightCode: undefined`，免得预览行被额外缩进或高亮改写。
- **竖线不是插件画的**：每行只发 `> `，`│ ` 由 pi 的 blockquote 渲染器逐行补。别改回自己塞
  `│ `：那两列会进 markdown 语法，`│ ``` ` 不再是 fence（行首最多 3 空格）→ 代码块降级成段落 →
  ``` 配成跨行 code span → CommonMark 把 code span 内换行变空格 → 折好的行合并成一条超长行 →
  pi 再折一次、后续行没有前缀，正文画到竖线那一列。交给 pi 之后竖线在结构上不可能再丢。
- **硬换行用行尾两个空格，不用 `\`**：反斜杠会被 autolink 吃进 URL 文本（裸 URL 结尾接 `\`
  会让 pi 把链接拆成两行、多出一行）；两个空格正常终结 URL 与行内代码。
- 展开态直接返回 `**Thinking**` + 原 markdown：不套引用所以没有竖线，也不做任何折行。
- 已知限制：折叠态代码行是行内代码配色（`codeBlock` 被顶替），与展开态代码块颜色不同；正文自带的
  标题/表格等块级结构会各自多占行，所以折叠高度不总是 6 行；`… +N rows` 按「去掉围栏标记行」
  之后的行数算；样式只能借 pi 的 markdown 主题（竖线走 `quoteBorder`，正文走 thinkingText），
  qoder 那种「侧栏一个色、标题一个色」做不到。
- 切换后靠 `ctx.ui.setHiddenThinkingLabel()` 逼 pi 重建 thinking 的 Markdown 组件（pi-tui 的
  Markdown 按 `(text,width)` 缓存，光 requestRender 不会重跑 transformer）。副作用：隐藏 thinking
  时那行标签会被重置回 pi 默认的 `Thinking...`。
- 折叠键 `ctrl+t` 是从 pi 内置动作手里拿来的：`ctrl+t` 默认属于 `app.thinking.toggle`，而它在
  `RESERVED_KEYBINDINGS_FOR_EXTENSION_CONFLICTS` 里，扩展注册同键会被直接拒绝。所以
  `keybindings.json` 里 `app.thinking.toggle` 改绑 `ctrl+shift+t`，并清掉 `/tree` 里也占 ctrl+t 的
  `app.tree.filter.noTools`（不清会多一行启动告警）。`/fold` 命令等价于按 `ctrl+t`
- 回归检查：`node pi/tests/thinking-fold-render.mjs` —— 把 transformer 的输出喂回**真** pi-tui 的
  `Markdown`；期望行直接调扩展导出的 `renderPreviewRows`（预览行只有这一份口径），逐行核对竖线、
  内容、`+N`、codeSpan 载体、ANSI 样式集、无超宽行，另加一条独立断言「输出里不得残留哨兵串」；
  展开态要求与原始渲染逐行一致。规模：36 样本 × 17 宽度 ×
  折叠/展开 + 18 个代码字面量 + 样式用例 + 逐字符流式（含 fold 切换与缓存失效）= 11228 组合。
  token 标记必须是**零宽** ANSI：可见标记自己占宽度，会把贴近预算的行挤到折行。样本覆盖列表项惰性
  续行（有序/无序）、列表空行后另起段、列表里的 fence、行内标记撑宽、嵌套/跨行行内标记、链接
  （text ≠ href）、转义字符、半截 fence/math/链接、长 autolink、表格、checkbox 嵌套列表、
  entities、CJK/emoji——都是折叠高度漂移的历史来源。包位置由脚本顺着 `command -v pi` 往上找
  （深 6），可用 `PI_AGENT_PKG` / `PI_TUI_PATH` 覆盖

## footer（常见坑：只有一个槽位）

`ctx.ui.setFooter()` 是**独占**的：谁最后调谁接管，`setFooter(undefined)` 才还给内置实现，也拿不到内置渲染器做叠加。所以以前 `tps-status` 一旦占位，其他扩展 `setStatus()` 写的东西就得看它有没有把 `getExtensionStatuses()` 抄进去。

现在统一走 `extensions/lib/footer.ts`：

- `footer-host.ts`（~5 行）是**唯一**调 `setFooter` 的扩展
- 其他扩展 `registerFooterProvider({ id, kind, render })`：`kind: "chip"` 右对齐在第一行，`kind: "line"` 自己占行（`order` 小的靠上）
- 仍用 `setStatus()` 的扩展照旧显示（host 会把它们当 chip 渲染）；id 和 status key 同名时 provider 优先，不会画两遍
- 注册表挂在 `globalThis.__piFooterProviders`（扩展由 jiti 分别实例化，模块级变量不保证只有一份；同 id 在 `/reload` 后自然覆盖）
- `lib/` 不是扩展目录：pi 只扫顶层 `.ts` 和含 `index.ts`/`index.js` 的子目录
- 新增 footer 内容时只需写一个 provider，不用改别人的文件

## models.json（provider/model override）

用 symlink 管理，因为 pi **只读**它：`ModelConfig.load()` 用 `readFile`，全 dist 搜不到任何对
`models.json` 的写操作；官方文档也把它定义为用户手工编辑的配置。

为什么 symlink 安全而 settings.json 不行——注意 pi 会写的两个“邻居文件”的路径来源：

- `models-store.json` = `dirname(modelsPath)/models-store.json` → 落在 `~/.pi/agent/`，**不经过** symlink
- `commandcode-models.json` = `join(getAgentDir(), "...")` → 同上

两者都按目录拼接，不是按 symlink 解析，所以不会反向污染 dotfiles。

升级/换机行为（`link_file` 逻辑）：

| 本机状态 | 动作 |
|---|---|
| 无文件 | 建立 symlink |
| 已是 symlink | skip |
| 真实文件且与 dotfiles **相同** | 删掉换成 symlink（不丢内容） |
| 真实文件且与 dotfiles **不同** | 报 conflict 并保留，不覆盖 |

## 不要纳入版本控制

`~/.pi/agent/` 下这些是运行时时序/机密，**不要**复制进 dotfiles：

- `auth.json` — 凭据
- `models-store.json`、`commandcode-models.json` — 运行时缓存（pi / provider 写入）
- `simple-perm-state.json` — simple-perm 记住的上次模式（扩展写入）
- `npm/`、`sessions/`、`tmp/`
