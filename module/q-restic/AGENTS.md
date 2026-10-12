# q-restic 工作指引

## 适用范围

本文件适用于 `module/q-restic/` 目录。

## 组件职责

- `q-restic.py`：唯一入口，同时是 CLI 和 TUI。仅用 Python 3 标准库。
  - CLI 子命令给脚本/定时任务用；不带参数且 stdin 是 tty 时进 TUI。
  - TUI 的备用屏、cbreak、SIGWINCH 唤醒管道、CJK 宽度计算都对齐根目录 `setup.py` 的写法，改交互时先读那份。
- `excludes.txt`：restic 排除清单，`q-restic edit-excludes` 可直接编辑。
  **路径里不要写死 `/home/<用户名>`**：restic 用 `os.ExpandEnv` 展开 exclude 文件里的环境变量
  （`~` 不展开，字面 `$` 写 `$$`），所以统一写 `$HOME/...`，换机器/换用户名都不用改。
  `restic_env()` 里 `env.setdefault("HOME", ...)` 是兼底：HOME 缺了的话 `$HOME/.cache`
  会展开成 `/.cache`，排除静默失效，几十 G 缓存会被传上去。
- `pyproject.toml`：无依赖，只为让 `uv run --project` 能起。
- 入口链接在根仓库 `bin/common/q-restic`，由 `q-python-install q-restic.py` 生成，**不要手改**
  （它是 runner.sh + uv 的 launcher，改命令名要重新生成）。
- 系统级定时由 `nix/modules/restic-home.nix` 负责，**它直接调 python3 而不是那个入口**：
  定时任务不该依赖 uv / `.venv` / flake 求值，而本脚本只用标准库。

## 关键不变量（都是实测踩出来的，改动前先看）

- **子命令别名要用 `in (...)` 分发**：`status` 挂了 `snapshots` / `list` 别名（restic 自己的命令就叫
  `snapshots`，旧版 bash 脚本也用 `--snapshots`）。用别名调用时 argparse 把 `args.command` 设成**别名本身**，
  只判 `== "status"` 会漏掉，然后落到末尾的 TUI 分支——表现是“想列版本却把 TUI 打开了”。
- **子进程的输出必须在备用屏外展示：`wait_key()` 要写在 `suspend()` 里面、`resume()` 之前**。
  先 `resume()` 会切回备用屏，把子进程打在普通屏上的东西整个盖掉，
  表现就是“跑完 diff 只剩一句按任意键返回，看不到内容”或者“只说失败、不说为什么”。
  现在失败时都先等一个键：`run_suspended()`（backup/dry-run/check）、`act_diff`、
  `act_restore`、`act_forget_snap`、`act_unmount`。新加 suspend 要子进程的操作时照此处理。
  **dry-run 是「成功也要等」的那种**：它的产出就是屏幕上那份“会新增/修改哪些文件”的清单，
  用 `run_suspended(..., wait_on_success=True)`。早先只判失败，于是 dry-run 一跑完就 `resume()`，
  清单被备用屏整个盖掉，用户只看到底部一句“试运行结束，仓库未改动”。
  `wait_key()` 自己会临时切 cbreak——`suspend()` 已把终端还原成 cooked，直接 read 要等回车，
  不然提示里的“任意键”不成立。
- **备份退出码 3（有文件读不到、快照已建）也要跑 `forget --prune`**，别改成“非 0 就跳过”：
  看起来 prune 会删掉这些文件在旧版本里的最后副本（代价是真的），但反过来更大：home 里只要有一个
  长期读不到的文件（root 600 之类），prune 就永远不跑，保留策略**静默失效**、旧版本无限堆积。
  只有 1（没建快照）和 10/11/12（仓库不存在/被锁/密码错）才完全不碰仓库。退出码要如实返回。
- **区分两套锁**：q-restic 自己的 flock（`~/.cache/q-restic.<repo hash>.lock`，只保护写流程）
  和 **restic 仓库锁**（`restic list locks`）。后者是另一个东西：进程被强杀
  （SIGKILL，或 `forget --prune` 跑到一半被 Ctrl-C）会留下残留锁，之后 `forget --prune`
  因为拿不到排他锁而失败——表现就是“删除失败”，而且每晚定时任务会在 forget 这步挂掉。
  清理用 `q-restic unlock`。`act_forget_snap` 会识别输出里的 `already locked` 并直接把这条命令提示给用户。
- **`selected_snap()` 不能用 `self.cursor` 索引**。在 `snap_actions` 屏里 `cursor` 指的是操作项
  （进屏时被重置为 0），拿它去索引 `self.snaps` 会**永远指向第一个版本**，
  于是“恢复/对比/删除这个版本”全作用在错误的版本上。离开版本列表时把选中项记进
  `self.active_snap`（见 `activate()`），`selected_snap()` 只读它。
- **diff 输出要过 `colorize_diff_line()`**：restic 的 diff 是纯文本（TTY 下也只有进度擦除序列），
  `+/−/M/T` 全一个颜色很难扫。标记行的判定必须**带上后面四个空格**——光看首字母会把
  `Dirs:` / `Files:` / `Others:` / `comparing` 的首字母当成变更。
- **kitty IME 闸门必须成对，离开时必须开闸**。q-restic 全程只做导航，所以进 TUI 就发
  `OSC 1337;SetUserVar=tui-bridge=<base64>`（`method=normal`）关掉 kitty 的 IME。
  kitty 是**旁路** IME 而不是切输入源，**留着关闸状态出去，用户手动切输入源也救不回来**
  （逃生阀是 kitty.conf 的 `ctrl+b>i enable_ime`）。所以 `KittyIMEGate` 把这些路径全挂上了：
  正常退出/异常（`main()` 的 `finally` + `atexit`）、`SIGTERM`/`SIGHUP`/`SIGQUIT`、
  `SIGTSTP` 挂起（挂起期间 shell 要能用，`SIGCONT` 后重新关闸）。
  改 TUI 入口/退出流程时别把这些拆掉。
- **字节必须与其它组件一字不差**：同一串 base64 在 `zsh/vi-im-switch.zsh`、
  nvim 的 `misc/ime/osc/backend.lua`、`kitty/tabpick.py`、`wezterm/tabpick.py` 里都在用。
  kitty 在 C 层（`vt-parser.c`）直接识别，没有任何子进程参与。规则见 kitty fork 的
  `AGENTS.md`「特性：按 window 彻底禁用输入法」。
- **`reassert()` 不能省**。`Terminal.resume()` 里会调它：TUI 挂起去跑子进程时，子进程可能
  自己动过闸门 —— nvim 退出时会发 `insert` 开闸，回到 TUI 就变成 IME 又开着，
  `j`/`k` 会被输入法吃掉。`disable()` 是幂等的（`armed` 为真就不再发），
  所以这种情况必须用会强制重发的 `reassert()`。
- **只往 `xterm-kitty` 发**：`terminal_is_kitty()` 在 tmux 内改问
  `tmux display-message -p '#{client_termname}'`（tmux 会改写 `TERM`）。tmux 会吞掉这个 OSC，
  所以 `TMUX` 存在时要用 DCS passthrough 包一层（内层 ESC 加倍），依赖 tmux 的
  `allow-passthrough on`。

- **启动路径不能阻塞**。版本列表由 `start_load()` 的后台线程拉取，首屏必须先画出来（实测 0.09s），
  加载完成后靠 `select` 超时自动重绘。不要在启动时调 `restic stats`：冷缓存下它要 4 秒以上
  （要遍历 44 万个文件），而界面需要的信息在 `snapshots --json` 的 summary 里已经有了。
  同步刷新用 `refresh()`，只在执行完动作后调用（那时已经 suspend 过，用户可接受等待）。
- **`select.select` 的超时是第 4 个位置参数**。写成 `select.select(rl, wl, [0.15])` 会把浮点数
  当成 xlist 而报 `TypeError: argument must be an int, or have a fileno() method`。正确写法：
  `select.select(rl, wl, [], 0.15)`。
- **光标本（cursorline）的底色要铺满整行**。做法是聚焦行行尾只发 `KEEP_BG`（清前景/粗体、
  不动背景），让 `render()` 里紧跟的 `\033[K` 用当前背景色填到行尾；`render()` 再给**每行开头加 `\033[0m`**，
  否则上一行的背景色会串到下一行。在行尾直接发 `RESET` 是早期版本的毛病，那样底色只到文字为止。
- **TUI 交互是「导航 + Enter」，不要加固定字母快捷键**。所有屏幕共用一套键：
  `↑↓/jk` 移动、`g/G`（及 Home/End）首尾、`PgUp/PgDn` 翻页、`Enter` 激活、`Esc` 返回上一层、
  主菜单里 `q` 退出。子页面靠 `item["goto"]` 切屏、`item["run"]` 执行动作，
  新增功能只要往 `menu_items()` / `snap_action_items()` 里加一项。
  菜单不设「退出」项，退出靠 `q` / `Esc`（`go_back()` 在菜单层返回 "quit"），底部提示里有说明。
  改键位要同步 `footer()` 里的 `ladders`，那是宽度不够时的提示降级链。
- **每个屏幕都必须实现移动键**。早期版本 `handle_menu()` 根本没处理 `j/k/UP/DOWN/ENTER`，
  菜单画了光标却移不动、只能靠字母跳——修改交互后一定要用 pty 测试确认光标真的会动。
- **CSI 序列不止 `A/B/C/D`**：方向键之外还有 `5~/6~`(PgUp/PgDn)、`1~/4~`(Home/End)，
  且 prefix 可能是 `ESC [` 也可能是 `ESC O`。统一查 `CSI_KEYS` 表，不要只读一个字节。
- **`--host` 只有部分子命令支持**：`snapshots` / `stats` / `forget` / `restore` / `mount` 支持；
  `diff` / `check` **不支持**，传了会直接报 `unknown flag`。用 `host_args()` 按命令挑选，
  不要像早期版本那样无差别给所有命令加。
- **只读操作不占备份锁**。`status` / `mount` / `browse` / `unmount` 必须在 `acquire_lock()` 之前
  返回，否则备份跑着时连状态都查不了（restic 自己的锁本来就允许并发读）。
- **锁文件路径必须与执行环境无关**：交互 shell 里 `XDG_RUNTIME_DIR` 有值，systemd 服务里是空的，
  用它做前缀会得到两个不同的锁，手动跑和定时跑撞在一起时保护失效。现在用 `$HOME/.cache/q-restic.<仓库hash>.lock`，
  按仓库区分，同一仓库串行、不同目标可并行。
- **不要对已含 ANSI 转义的字符串调 `fit()`**：转义字节会被算成可见宽度而提前截断。
  底部提示的宽度控制靠 `footer()` 里的阶梯降级完成。
- **版本列表每行的「数据量 / 新增」两列在 `body()` 里拼**：字段是 `size`（`snap_size`）和
  `added`（`snap_added`，前面带 `+`，没有 summary 就留空），列宽按本屏实际数字算，
  时间戳固定 19 列所以带数字列时 `label_w` 收到 20。
  ⚠️ `avail_w` 是给**整个 desc（数字列 + 标签）**的预算，`fit()` 就 fit 到 `avail_w`；
  写成 `avail_w - cols_w` 会把数字自己截掉（000.4 G…）。标签位不够 6 列时退回
  把「数据量 新增 标签」全塞进 desc。
- **restic 必须已在 PATH 里**，不再用 `nix build nixpkgs#restic` 兜底（多次求值 flake、
  systemd 服务里没网络保证）。由 `nix/modules/restic-home.nix` 提供，且**两个选项都得配**：
  `environment.systemPackages` 只影响 `/run/current-system/sw/bin`（手动执行的 PATH），
  `systemd.services.<name>.path` 才是 unit 的 PATH 来源（求值时按 `enableDefaultPath`
  生成 coreutils/findutils/gnugrep/gnused/systemd）。只写 systemPackages 的话手动跑没事、
  定时任务天天失败在“PATH 里找不到 restic”，**rebuild 多少次也不会好**。同一坑的第二口是 `ssh`：
  unit 里还得有 `pkgs.openssh`，因为 `preflight_sftp()` 自己调 ssh；restic 的 sftp 后端是
  Go 原生实现、不需要 ssh（实测 PATH 清空也能列快照），所以 ssh 缺了只影响预检，
  现在会 warn 跳过而不是抛堆栈。反过来，别把 `detect_host()` 改回 `hostname -s`：
  那个二进制来自 net-tools、不在 unit 的 PATH 里，新机器（还没有 config.json）会直接
  FileNotFoundError；现在用 socket.gethostname()。
- **`restic snapshots --json` 的 `summary` 里没有 `total_size`**，那个名字只存在于 `restic stats` 的输出。
  版本数据量取 `summary.total_bytes_processed`，该版本实际写入量取 `summary.data_added_packed`。
- **restic 时间戳是纳秒精度**，Python 3.9 的 `datetime.fromisoformat` 不接受，排序用 `snap_time_key()` 截到秒。
- **`--one-file-system` 不能用**：`/home` 下没有嵌套挂载点，加了只会平白跳过东西。
- 仓库走 SFTP 而不是 CIFS 挂载点：restic 依赖 fsync + rename 原子性，而 fstab 里的 CIFS 用了
  `soft` + `cache=strict`，NAS 卡顿时返回 EIO 而不是等待，那正是会写坏仓库的语义。

## 保留策略语义

`--keep-{hourly,daily,weekly,monthly,yearly}` 是**桶**语义：每个时间桶最多留一个，多条规则取**并集**。
另外「桶装不满时额外保留最老的那个」，所以版本很少时会看到全部被保留。

## 验证原则

- 改完至少跑 `python3 -m py_compile q-restic.py`。
- **`config` 子命令的 stdout 必须保持纯 JSON**（提示信息一律走 stderr），
  否则 `q-restic config | jq` 会解析失败。验证：`q-restic config 2>/dev/null | python3 -m json.tool`。
- 改 CLI / 保留策略：先用 `q-restic dry-run` 空跑，或在临时仓库上验
  （`XDG_CONFIG_HOME=<临时目录>` 指向一个本地仓库，不要拿真仓库试）。
- 改 TUI：不能靠 `script` 喂 stdin（管道转发不可靠，按键会丢），用 `pty.fork()`
  起子进程、延迟写入按键再读回输出，见开发时用的 pty 测试法。
- 改 IME 闸门：设 `Q_RESTIC_IME_DEBUG=<file>` 会把每次开关记进文件（带 `armed` 状态），
  比在 pty 输出里找转义序列简单。四条路径都要测：正常退出、`SIGTERM`、`SIGTSTP`+`SIGCONT`、
  非 kitty 终端（`TERM=xterm-256color` 时必须完全不发）。想验证 tmux 包装就把
  `TMUX` 和 `TERM=xterm-kitty` 一起设上，检查输出里有 `\ePtmux;`。
  **测试务必跑在新建的 pty 里**，否则这些转义会写到你自己的终端窗口、真把 IME 关掉。
- **测试要收尾干净**：pty 测试里 kill 掉一个正在跑 restic 的进程会在仓库里留下 restic 锁
  （测试仓库就攒了好几把），之后 forget/prune 全失败。跑完用 `restic unlock` 清一下；
  另外 TUI 里按到“挂载并浏览”会真的挂盘、按到“编辑保留策略”会真的开 `$EDITOR`
  （没设 `EDITOR` 就是 nvim），导航测试别按过头，并给测试设 `EDITOR=/tmp/fake-editor.sh`。
- 改动写入路径后确认并发保护仍生效：同一仓库同时跑两个实例，第二个应报
  `另一次备份正在运行`。
