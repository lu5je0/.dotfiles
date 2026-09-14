# pi 配置

pi（coding agent）的用户级配置目录：`~/.pi/agent/`。本目录由 `scripts/setup.d/modules/unix/pi.sh` 部署。

## 部署方式

- 子目录（如 `extensions/`）→ symlink 到 `~/.pi/agent/<name>`（整目录链接，实时生效）
- `models.json` → symlink（pi 只读它，不写）
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
- `npm/`、`sessions/`、`tmp/`
