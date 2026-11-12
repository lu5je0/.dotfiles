# q-restic 工作指引

## 适用范围

本文件适用于 `module/q-restic/` 目录。

## 组件职责

- `q-restic.py`：唯一入口，同时是 CLI 和 TUI。仅用 Python 3 标准库。
  - CLI 子命令给脚本/定时任务用；不带参数且 stdin 是 tty 时进 TUI。
  - TUI 的备用屏、cbreak、SIGWINCH 唤醒管道、CJK 宽度计算都对齐根目录 `setup.py` 的写法，改交互时先读那份。
- restic 排除清单由 profile 的 `excludes` 引用；主机配置与清单放在 Nix 主机目录，不放工具代码目录。
  可写清单用 `q-restic -p <profile> edit-excludes` 编辑，Nix 部署的只读清单修改源文件后 rebuild。
  exclude 路径用 `$HOME/...`：restic 展开环境变量，不展开 `~`，字面 `$` 写 `$$`。
  `restic_env()` 补齐缺失的 HOME，避免排除路径展开错误。
- `pyproject.toml`：声明 Python >= 3.9，无第三方依赖。
- `.script`：声明 `SCRIPT_RUNNER=python3`，入口通过 runner.sh 调用系统 Python，不创建或同步 `.venv`；root 运行禁用字节码写入。
- 入口脚本 `bin/common/q-restic` 由 `q-python-install q-restic.py` 生成；运行方式在 `.script` 中调整后重新生成。
- huskar 系统级定时由 `nix/nixos/hosts/huskar/q-restic/default.nix` 配置，直接调用 Python 3 标准库脚本。

## 配置与 profile

- 根配置格式是 `{"profiles": {...}}`，详见同目录 `README.md`。
  新 profile 必须显式配置 `sources` 列表、`repository`；不能隐式备份 home。
  `-c/--config`、`-p/--profile` 可置于子命令前后，CLI 仓库操作必须指定 profile。
- `load_config()` 返回整个文档，`profile_config()` 返回解析路径及私有上下文的有效配置。
  `imports` 递归合并 profiles，缺失文件、循环与重名均报错，不允许覆盖。
  默认入口自动合并 `/etc/q-restic/config.json` 与用户配置，任一不存在可跳过；
  `-c` 指向其它入口时不自动加载系统配置。系统 profile 的来源与相对路径仍指向系统文件。
  路径与 hooks cwd 相对定义 profile 的文件目录；符号链接以声明路径目录为基准。
  `ConfigDocument` 的属性记录来源与入口原文，不进入 JSON；保存入口保留 imports，不能展开合并视图。
  编辑保留策略定位来源文件，不能把其它 profile 丢掉，也不能写回私有字段；Nix 文件拒绝直接编辑。
- snapshot_tag 可显式指定快照筛选标签；未配置时自动使用 profile 独立标签。
- 所有支持快照筛选的命令都通过 `snapshot_args()` 传主机和 profile 标签。
  restore 对显式 ID 也先检查是否属于当前 profile，因为 restic 原生筛选只约束 latest。
  同仓库同主机的 profile 标签不能互相匹配；写锁仍按仓库区分，check/unlock 操作整个仓库。
- TUI 默认从 profile 列表开始，首屏不访问仓库、不要求 restic 已经可用。
  切换 profile 时废弃所有旧异步请求，不能把上一 profile 的版本、统计或错误带过来。
- 仓库未初始化是独立状态：TUI/CLI status 只提示，不初始化；首次 backup 才创建。
  错误凭证、权限和连接失败不得当成空仓库，也不得触发初始化；已有列表遇到仓库消失仍保留列表并报错。
  未初始化时不读取占用；异步结果切换 profile 后不能带入此状态。
- 仓库密码统一为内置 `lu5je0`，不读取 password_file 或继承外部密码设置；没有设置密码菜单/命令。
  错误密码仍是认证失败，不自动改密钥或初始化仓库。
- `run_as` 指定 restic 和运行文件的用户；`hooks_run_as` 显式覆盖 hooks 身份，默认继承 run_as。
  未配置时保留启动身份。root 通过 Popen 的 user/group/extra_groups 切换子进程身份，不能在
  多线程 TUI 父进程里 setuid 或使用 preexec_fn。普通用户不自动提权。
  显式用户的 HOME/XDG 路径固定于账号 home，锁和挂载日志必须由目标用户打开；通过 Unix socket
  传回描述符让父进程持锁，不能让 root 直接打开用户可写路径。已有文件权限不自动迁移。
  hooks 获得 Q_RESTIC_RUN_AS/Q_RESTIC_UID/Q_RESTIC_GID；root hook 负责让导出文件可被备份用户读取。
  huskar 的 systemd 服务以 lu5je0 运行并授予 CAP_DAC_READ_SEARCH，读取 root 私有源文件；
  同 UID 子进程必须保留 ambient capability，不能无条件 setuid/drop capabilities。
  日常 CLI/TUI 不带此权限；完整手动备份走 restic-home.service，排除清单照常生效。

- `hooks` 可配置 preflight/before_backup/after_backup 的 argv 列表，不经过 shell，cwd 是配置目录。
  写锁覆盖准备、备份、恢复和清理；after_backup 在准备失败或异常时也执行，且早于清理。
  恢复失败返回非零并跳过清理；dry-run 不执行 hooks。终止信号要经过 finally。

## 关键不变量

- **子命令别名**：argparse 的 `args.command` 保留用户输入的别名；分发 `status` 时同时处理 `snapshots` / `list`。
- **子进程输出**：在普通屏展示，失败时于 `suspend()` 内等待按键，再 `resume()`，避免错误信息被备用屏覆盖。
  dry-run 成功时也通过 `run_suspended(..., wait_on_success=True)` 等待用户查看清单。
  `wait_key()` 临时启用 cbreak，使单键输入无需回车。
- **备份退出码 3**：表示存在不可读文件但快照已创建，仍执行 `forget --prune`，并如实返回 3，保持保留策略生效。
  这可能清除不可读文件的旧副本；未创建快照或仓库错误时不清理。
- **清理失败不能打印“完成”或返回成功**：备份成功后，`forget --prune` 的失败码必须传到 CLI / systemd；
  备份本身为 3 时仍保留 3，但要明确输出清理失败。TUI 对退出码 3 不能一概宣称“已清理旧版本”。
- **区分两套锁**：q-restic 的 flock（`~/.cache/q-restic.<repo hash>.lock`）保护本机写流程，退出时释放；
  restic 仓库锁通过 `restic list locks` 查看，强制结束进程可能留下残留锁。
  `q-restic -p <profile> unlock` 清理残留锁，`act_forget_snap` 遇到 `already locked` 时提示此命令。
  `unlock` 也要拿 q-restic 的写锁，只用 restic 默认的残留锁清理，别加 `--remove-all`；读取锁失败不能说成“没有锁”。
  正式备份在本机写锁内、仓库确认或初始化后自动执行默认 `unlock`；活动锁判断交给 restic，
  不用进程列表替代 flock 或仓库锁。自动清理失败时仍跑 after_backup，但不启动备份或清理旧快照；dry-run 不解锁。
- **快照选择**：`activate()` 将选中快照保存到 `self.active_snap`，`selected_snap()` 读取此值。
  操作菜单的 `self.cursor` 表示菜单项，不能用来索引快照。
- **版本 diff 交给 Neovim 展示**：restic stdout 直接写临时 `.diff` 文件，以只读、不可修改的
  diff buffer 打开 `nvim`，不在 TUI 中自行渲染。退出编辑器后清理临时文件并恢复 TUI；
  restic 或编辑器失败时在普通屏等待按键，错误不能被备用屏盖掉。
- **kitty IME 闸门**：进入 TUI 时发送 `OSC 1337;SetUserVar=tui-bridge=<base64>`（`method=normal`）禁用 IME，离开时恢复。
  kitty 在此执行 IME bypass，不切换输入源；未恢复时切换输入源也不会启用 IME。
  `KittyIMEGate` 覆盖以下路径：
  正常退出/异常（`main()` 的 `finally` + `atexit`）、`SIGTERM`/`SIGHUP`/`SIGQUIT`、
  `SIGTSTP` 挂起（挂起期间 shell 要能用，`SIGCONT` 后重新关闸）。
  修改入口与退出流程时保留这些恢复路径。
- **IME 协议字节一致性**：`zsh/vi-im-switch.zsh`、nvim 的 `misc/ime/osc/backend.lua`、
  `kitty/tabpick.py`、`wezterm/tabpick.py` 使用相同的 base64 序列，kitty 在 `vt-parser.c` 中直接匹配。
  规则见 kitty fork 的
  `AGENTS.md`「特性：按 window 彻底禁用输入法」。
- **恢复 TUI 时重发闸门**：子进程可能修改 IME 状态；`Terminal.resume()` 调用 `reassert()` 强制重发。
  `disable()` 在 `armed` 为真时不发送，不能用于此恢复路径。
- **只往 `xterm-kitty` 发**：`terminal_is_kitty()` 在 tmux 内查询
  `tmux display-message -p '#{client_termname}'`（tmux 会改写 `TERM`）。tmux 会吞掉这个 OSC，
  所以 `TMUX` 存在时要用 DCS passthrough 包一层（内层 ESC 加倍），依赖 tmux 的
  `allow-passthrough on`。

- **启动路径不能阻塞**：首屏先绘制，版本列表由 `start_load()` 后台加载，靠 `select` 超时重绘。
  `restic stats` 需要遍历仓库，不在首屏同步调用。版本数据量取 `snapshots --json` 的 summary；版本列表底部的
  总占用在进入版本列表后由 `start_stats_load()` 后台读取 `stats --mode raw-data`
  （与 CLI 一样按 host 和 profile 标签过滤），会话内缓存；备份、删除、仓库/host/执行用户变更，
  或新版本列表与缓存不同时失效。只读操作不触发重新统计。
  `refresh()` 也必须后台执行、保留已有列表，失败不能清空列表或冒充空仓库；
  `snapshots()` 遇到命令失败/无效 JSON 必须抛错，CLI status 返回非零。
  后台线程只往队列投递结果，由主线程 `poll_data()` 更新界面，旧请求不能覆盖新结果。
  错误单独保存在 `load_error` / `repo_size_error`，导航不能清除；失败后返回主菜单
  再进入版本列表时自动重试。统计失败显示不可用，不当成 0。
- **cursorline 底色**：聚焦行末尾使用 `KEEP_BG` 保留背景，让 `\033[K` 填满整行；每行开头 `\033[0m` 重置样式，避免背景串行。
- **TUI 交互**：所有屏幕共用导航键：
  `↑↓/jk` 移动、`g/G`（及 Home/End）首尾、`PgUp/PgDn` 翻页、`Enter` 激活、`Esc` 返回上一层、
  profile 列表里 `q` 退出，菜单里 `q` 返回 profile 列表。子页面靠 `item["goto"]` 切屏、`item["run"]` 执行动作，
  菜单项在 `menu_items()` / `snap_action_items()` 中声明。完整性校验入口为 CLI `q-restic -p <profile> check`。
  退出使用 `q` / `Esc`（`go_back()` 在没有上层时返回 "quit"）。
  改键位要同步 `footer()` 里的 `ladders`，那是宽度不够时的提示降级链。
- **导航验证**：修改交互后用 pty 测试覆盖各屏幕的移动键与 Enter。
- **CSI 序列不止 `A/B/C/D`**：方向键之外还有 `5~/6~`(PgUp/PgDn)、`1~/4~`(Home/End)，
  且 prefix 可能是 `ESC [` 也可能是 `ESC O`。统一查 `CSI_KEYS` 表，不要只读一个字节。
- **`--host` 只有部分子命令支持**：`snapshots` / `stats` / `forget` / `restore` / `mount` 支持；
  `diff` / `check` 不支持。通过 `snapshot_args()` 按命令选择参数。
- **只读操作不占备份锁**。`status` / `mount` / `browse` / `unmount` 必须在 `acquire_lock()` 之前
  返回，否则备份跑着时连状态都查不了（restic 自己的锁本来就允许并发读）。
- **挂载入口消失不代表挂载进程已退出**。Linux 卸载和重新挂载前通过 `/proc` 核对用户、仓库、
  挂载路径、host/tag 参数并回收残留 `restic mount`，不能按进程名批量结束 restic。
  发信号前复核启动时间，支持时使用 pidfd 防止 PID 复用；SIGTERM 后超时必须报错。
  `browse` 启动失败、超时或等待被中断时也要 terminate/wait，不能丢下后台子进程。
- **锁文件路径与执行环境无关**：使用 `$HOME/.cache/q-restic.<仓库hash>.lock`，使 shell 与 systemd 共用本机写锁；
  同一仓库串行，不同仓库可并行。
- **不要对已含 ANSI 转义的字符串调 `fit()`**：转义字节会被算成可见宽度而提前截断。
  底部提示的宽度控制靠 `footer()` 里的阶梯降级完成。
- **版本列表每行的「数据量 / 新增」两列在 `body()` 里拼**：字段是 `size`（`snap_size`）和
  `added`（`snap_added`，前面带 `+`，没有 summary 就留空），列宽按本屏实际数字算，
  时间戳固定 19 列所以带数字列时 `label_w` 收到 20。
  `avail_w` 是整个 desc（数字列 + 标签）的预算，`fit()` 使用 `avail_w`；标签位不够 6 列时，
  将「数据量 新增 标签」统一放入 desc。
- **运行依赖**：restic 从 PATH 查找；SFTP 还需要 ssh。huskar 的 Nix 模块同时设置交互环境的
  `environment.systemPackages` 与服务的 `systemd.services.<name>.path`，服务 PATH 包含 restic 和 openssh。
  `preflight_sftp()` 缺少 ssh 时警告并跳过预检，连接错误由 restic 报告。主机名通过 `socket.gethostname()` 读取。
- **`restic snapshots --json` 的 `summary` 里没有 `total_size`**，那个名字只存在于 `restic stats` 的输出。
  版本数据量取 `summary.total_bytes_processed`，该版本实际写入量取 `summary.data_added_packed`。
  缺失统计返回 None，不能冒充 0；旧快照数据量通过 `stats --mode restore-size <ID>` 补齐，
  TUI 仅在版本页逐个后台查询并缓存，失败可重试，失效请求不得回写。旧快照新增量保持未知。
- **restic 时间戳是纳秒精度**，Python 3.9 的 `datetime.fromisoformat` 不接受，排序用 `snap_time_key()` 截到秒。
- NAS 仓库使用 SFTP，本地 ext4 仓库可直接写。restic 依赖 fsync 与原子 rename；当前 CIFS 挂载使用
  `soft` + `cache=strict`，连接异常可能返回 EIO，不作为仓库写入路径。

## 保留策略语义

`--keep-{hourly,daily,weekly,monthly,yearly}` 是**桶**语义：每个时间桶最多留一个，多条规则取**并集**。
restic 原生还有「桶装不满时额外保留最老的那个」的兜底；q-restic **取消这个额外保留**：
先读取 `forget --dry-run --json`，只把保留理由全部是 `oldest ... snapshot` 的版本加入
原生删除列表，再用完整 ID 执行 `forget --prune`。有任一正常保留理由的版本仍然留下。
每组至少保留一个版本；预览失败或格式不完整必须中止，不能继续删除。
`q-restic -p <profile> forget --dry-run` 可只读预览实际清理列表；`q-restic -p <profile> dry-run` 仍是备份预览。

## 验证原则

- 改完至少跑 `python3 -m py_compile q-restic.py`。
- 数据加载/刷新逻辑的回归测试：`python3 -m unittest discover -s module/q-restic/tests -p 'test_*.py'`。
- huskar 跨属主读取验证：`unshare --map-auto --map-root-user python3 -m unittest discover -s module/q-restic/tests -p test_backup_capability.py -v`。
  需要 Linux 用户命名空间及 subordinate UID/GID 映射；验证私有源文件不可读、带 capability 备份、
  撤掉 capability 后读取仓库、保留源权限和普通用户的仓库/缓存属主，不接触真实备份仓库。
- **`config` 子命令的 stdout 必须保持纯 JSON**（提示信息一律走 stderr），
  否则 `q-restic config | jq` 会解析失败。验证：`q-restic config 2>/dev/null | python3 -m json.tool`。
- 改 CLI / 保留策略：先用 `q-restic -p <profile> dry-run` 空跑，或在临时仓库上验
  （`XDG_CONFIG_HOME=<临时目录>` 指向一个本地仓库，不要拿真仓库试）。
- 改 TUI：使用 `pty.fork()` 启动子进程、写入按键并读取输出，验证真实终端交互。
- 改 IME 闸门：`Q_RESTIC_IME_DEBUG=<file>` 记录开关与 `armed` 状态。测试覆盖正常退出、`SIGTERM`、
  `SIGTSTP`+`SIGCONT` 与非 kitty 终端；`TERM=xterm-256color` 时不发送闸门序列。
  tmux 包装测试同时设置 `TMUX` 与 `TERM=xterm-kitty`，检查 `\ePtmux;`。
  在独立 pty 中测试，避免转义序列修改当前终端的 IME 状态。
- 测试使用临时仓库，结束时回收子进程、挂载与残留锁；导航测试设置模拟 EDITOR，避免启动真实编辑器。
- 改动写入路径后确认并发保护仍生效：同一仓库同时跑两个实例，第二个应报
  `另一次备份正在运行`。
