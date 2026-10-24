# q-restic

按 profile 管理 restic 备份的 Python 标准库 CLI / TUI。运行环境需要提供 `restic`；
NAS 可使用 SFTP，本地 ext4 等 POSIX 文件系统可直接作为仓库，避免直接写入 CIFS soft 挂载点。
入口直接使用系统 Python >= 3.9，不依赖 uv 或 `.venv`；root 运行时禁用字节码写入。

## 使用

```sh
q-restic                         # 先选择 profile，再进入操作菜单
q-restic -c /path/config.json     # 使用指定配置
q-restic -p home                  # 直接进入 home 菜单
q-restic -p home preflight        # 执行可选的 hooks.preflight 预检
q-restic -p home backup           # 备份并应用该 profile 的保留策略
q-restic -p home dry-run          # 只预览；不会初始化仓库
q-restic -p home status           # 列出版本及数据占用，别名 snapshots / list
q-restic -p home restore latest /path/restore
q-restic -p home forget --dry-run # 预览历史版本清理
q-restic -p home check            # 整个仓库的校验，不限于该 profile
q-restic -p home unlock           # 整个仓库的残留锁清理
```

`-c/--config`、`-p/--profile` 可放在子命令前或后。默认配置是
`~/.config/q-restic/config.json`，会自动合并 `/etc/q-restic/config.json` 中的 profiles，
两份文件均可缺省，profile 重名时报错；`-c` 指向其它文件时只读取该入口及其 imports。
CLI 仓库操作必须显式指定 profile，即使文件里只有一个；
未知 profile、显式指定的配置文件不存在时立即报错，不回退到 home 或其它仓库。
仓库尚未创建时显示「仓库未初始化」，首次 `backup` 自动创建；查看状态不会初始化仓库。
密码、权限或连接错误仍会报告读取失败。
TUI 首屏不访问仓库，进入 profile 后异步加载；`Esc/q` 返回 profile 列表，再按一次退出。

定时任务直接调用系统 Python，例如：

```sh
/usr/bin/python3 /path/q-restic.py -c /path/config.json -p home backup
```

## 配置

```json
{
  "profiles": {
    "home": {
      "sources": ["$HOME"],
      "repository": "sftp:user@nas:/backups/restic/home",
      "snapshot_tag": "home",
      "excludes": "./excludes.txt",
      "keep": {"daily": 7, "weekly": 4, "monthly": 1}
    }
  }
}
```

每个 profile 必须提供 `sources`（非空列表）、`repository`，不隐式备份 home。
路径支持 `~` 和环境变量，相对路径以配置文件所在目录为基准；SFTP 等仓库地址保持后端语法。
`excludes` 是可选的排除文件路径。排除文件内部的变量由 restic 展开，推荐使用 `$HOME`。

通过 `imports` 引入其他配置，例如在 `~/.config/q-restic/config.json` 中：

```json
{
  "imports": ["./personal.json"],
  "profiles": {}
}
```

支持递归导入，相对路径以声明它的配置文件所在目录为基准；profile 重名会报错，不会覆盖。
系统配置无需写入 `imports`。保存用户配置不会把系统或导入的 profiles 展平写回；
编辑某个 profile 时定位到它的来源文件，Nix 管理的文件需修改 Nix 配置后 rebuild。

`keep` 支持 hourly/daily/weekly/monthly/yearly 非负整数，未设置的项目为 0；全部为 0 时保留全部版本。
数量按非空时间桶取并集，不额外保留仅由 `oldest ... snapshot` 兜底的版本，每组至少保留一个。
备份不完整（退出码 3）时仍会清理旧版本并返回 3，清理失败也不会被当作成功。

`host` 默认使用本机短名。`tag` 可附加普通标签；程序另外自动使用 `q-restic:profile:<名称>`
区分 profile。列表、统计、挂载、恢复和清理都限制到当前主机及 profile 标签。
即使手工提供其它 profile 的快照 ID，也不能通过 `restore` 绕过范围检查。
`snapshot_tag` 可显式指定快照筛选标签，使用已有仓库时应与目标快照的标签一致。
多个 profile 共用仓库时，写锁仍按仓库区分，`check` 和 `unlock` 是仓库级操作。
不同 profile 的快照筛选标签不能互相匹配。

版本数据量优先读取快照的 `summary`。旧版 restic 创建的快照没有此字段时，TUI 在进入版本列表后
逐个后台调用 `stats --mode restore-size <快照 ID>` 补齐数据量，并在会话内缓存；查询前显示「统计中」，
失败显示「不可用」。CLI `status` 也会查询缺失的数据量，失败返回非零。
快照没有记录的新增量显示「未知」，不从仓库总占用推算，也不把缺失统计当成 0 B。

`mount_dir` 默认 `/tmp/restic-mnt/<profile>`，`restore_dir` 默认 `~/restic-restore/<profile>`。
多目录快照恢复后，各源目录的绝对路径树都位于恢复目标下。

`q-restic -p home browse` 只读挂载并用文件管理器打开，`q-restic -p home unmount` 卸载。
普通卸载因目录被占用而失败时，自动改用延迟卸载：立即移除挂载入口，现有访问结束后释放资源。
权限等其它错误仍会报错；不会终止占用目录的程序。

`q-restic config` 输出合并后的 JSON，`q-restic -p home config` 输出该 profile 解析后的配置；
提示信息不混入 stdout。

## 仓库密码

所有仓库统一使用内置密码 `lu5je0`，不读取密码文件，不提供密码设置菜单或 `set-password` 命令。
遗留配置中的 `password_file` 不再生效；环境中的 `RESTIC_PASSWORD_FILE`、`RESTIC_PASSWORD_COMMAND`
与 `RESTIC_PASSWORD` 不会覆盖内置密码。已有仓库必须已使用该密码；认证失败会直接报错，不自动改密钥或初始化。

## 执行用户

profile 可配置 `"run_as": "lu5je0"`。root cron 仍启动 q-restic，所有 restic 子进程
（包括查看、备份、清理、恢复、挂载）使用指定用户的 UID、主组和附加组。
未配置时沿用启动身份；普通用户不能切换成其他账号，需要通过 sudo 启动。
TUI 显示配置的执行用户；父进程保持启动身份，切换仅发生在子进程中。

显式指定用户后，`HOME`、`USER`、`LOGNAME` 与 XDG 配置、缓存、状态和数据目录统一按其账号设置；
`~` / `$HOME` 等 profile 路径按目标用户展开，相对配置路径仍基于来源配置目录。
配置入口和 imports 仍由启动用户解析，root cron 应显式传入 `-c`。
锁、缓存、挂载目录和挂载日志由目标用户创建；root cron 与该用户的手动操作共用
`<用户 home>/.cache/q-restic.<仓库 hash>.lock`。配置同一仓库的写入入口应使用相同 `run_as`。

hooks 默认也使用 `run_as`；需要 Docker 等 root 权限时，显式增加 `"hooks_run_as": "root"`：

```json
{
  "run_as": "lu5je0",
  "hooks_run_as": "root",
  "hooks": {
    "before_backup": ["/usr/bin/python3", "./hooks.py", "prepare"]
  }
}
```

上述片段放入现有 profile。此配置下 root cron 或 `sudo q-restic ... backup` 可以执行 root hook；
lu5je0 可直接查看和恢复，但执行备份会提示需要 sudo。不会自动提权或修改 sudoers。
`hooks_run_as` 可独立配置，未指定时继承 `run_as`，两项都未配置时沿用启动身份。

q-restic 不会递归修改现有仓库或备份源的属主。切换用户前应在没有备份任务运行时迁移本地仓库权限，
并确认该用户能读取所有备份源。root hook 产生的 SQL 等文件须由 hook 显式交给备份用户；
新恢复文件由目标用户创建，无法恢复其无权设置的其他账号属主。SFTP 远端属主仍由连接账号决定。

## 备份前后命令

profile 可选 `hooks` 对象，`preflight`、`before_backup` 和 `after_backup` 的值都是非空命令参数列表，
例如 `"before_backup": ["/usr/bin/python3", "./prepare.py"]`。命令直接执行，不经过 shell；
工作目录为定义该 profile 的文件所在目录，提供入口路径 `Q_RESTIC_CONFIG` 和 `Q_RESTIC_PROFILE` 环境变量。
配置 `run_as` 时还提供 `Q_RESTIC_RUN_AS`、`Q_RESTIC_UID`、`Q_RESTIC_GID`，供 root hook 设置导出文件属主。

`preflight` 只在显式执行 `q-restic -p home preflight` 时运行，不获取备份锁、不访问仓库；
未配置对应命令时返回错误。

取得仓库写锁后先执行 `before_backup`，成功才初始化仓库并备份。`after_backup` 在准备、
初始化或备份失败时也会执行，因此应能安全处理未完成的准备工作；它在旧版本清理之前执行。
恢复步骤失败会返回非零并跳过清理。`dry-run` 不执行这些命令，也不初始化仓库。
Ctrl-C、SIGTERM、SIGHUP 会经过恢复步骤；强制杀进程或断电需要准备脚本自行保留恢复状态。
