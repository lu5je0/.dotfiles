# pi 配置

pi（coding agent）的用户级配置目录：`~/.pi/agent/`。本目录由 `scripts/setup.d/modules/unix/pi.sh` 部署。

## 部署方式

- 子目录（如 `extensions/`）→ symlink 到 `~/.pi/agent/<name>`（整目录链接，实时生效）
- `models.json` → symlink（pi 只读它，不写）
- `simple-perm.json` → symlink（`simple-perm` 扩展只读它，不写）
- `keybindings.json` → symlink（pi 只在迁移旧式键位 id 时才回写，本文件全是新式 id）
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

## 权限（simple-perm 扩展）

`extensions/simple-perm.ts` 是自写的三模式权限扩展，零依赖，只需要 PATH 里有 `bwrap`：

| 模式 | 项目外读 | 项目外写 | bash |
|---|---|---|---|
| `ro`（默认） | 允许 | 拒绝 | bwrap 沙箱，项目+白名单+/tmp 可写 |
| `ask` | 允许 | 弹确认（可记住目录） | 同上 |
| `yolo` | 允许 | 允许 | 不沙箱 |

- 切换：`ctrl+y` 循环、`/perm <ro|ask|yolo|clear>`、启动 `--perm <mode>`、`PI_PERMISSION_MODE` 环境变量
- 模式会记住：切换时写 session entry（resume/`/reload` 生效）+ `~/.pi/agent/simple-perm-state.json`（下次启动生效）。启动优先级：`--perm` > 本 session 记录 > `PI_PERMISSION_MODE` > 状态文件 > 默认 `ro`
- 白名单：`simple-perm.json` 的 `allowWrite`（本目录），项目级可加 `.pi/simple-perm.json` 追加；列在这里的目录读写全放行，`/tmp` 恒可写
- 沙箱实现是 `tool_call` 里把 bash 命令改成 `bwrap --ro-bind / / --bind …`。因此只读区域里需要写 HOME 缓存的工具（npm/uv/cargo → `~/.cache`、`~/.npm`、`~/.cargo`）会失败，需要就写进 `allowWrite`；`/tmp` 已内置
- 项目本身在 `/tmp` 下时，`../x` 这类相对路径仍可写（`/tmp` 整个被 bind 成可写）
- bwrap 只映射当前 uid，root 拥有的文件在沙箱内显示成 `nobody`，于是 ssh 会因 `/etc/ssh/ssh_config` 的属主校验挂掉（`git push` exit 128）；扩展把 `~/.ssh` 盖到 `/etc/ssh` 上规避
- 注意：`!` 前缀的用户 bash 不走这条路径，不受沙箱约束

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
