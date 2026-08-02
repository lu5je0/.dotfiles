# Setup Modules 工作指引

## 概览

`setup.py`（仓库根目录，仅支持 Python 3）是 dotfiles 安装入口，提供 TUI 多选菜单，按模块执行安装。

```bash
python3 ~/.dotfiles/setup.py
```

模块按平台分目录存放在 `scripts/setup.d/modules/` 下：

- `unix/` — macOS / Linux / WSL / Termux（从 WSL 内部视角）
- `win/` — WSL 环境且 dotfiles 位于 `/mnt/c/` 时，操作 Windows 侧文件

平台自动识别：WSL + `DOTFILES_DIR` 在 `/mnt/c/*` 时加载 `win/`，否则加载 `unix/`。

## modules.json

每个平台目录下有一个 `modules.json`，顶层是数组，按声明顺序展示。

### LINK 模块

纯 symlink，无需 .sh 脚本：

```json
{ "name": "kitty", "source": "kitty", "target": "~/.config/kitty" }
```

- `source` 相对 `DOTFILES_DIR`，`target` 为链接位置
- `desc` 可选，省略时自动生成 `./<source> → <target>`
- `action` 可选，默认 `link`
- 状态从 target 推导（symlink 指向 dotfiles → installed）
- setup.py 自动处理 mkdir、symlink、skip

### SCRIPT 模块

复杂逻辑（多文件、下载、sudo 等），指向同目录下的 .sh 脚本：

```json
{
  "name": "termux",
  "action": "link",
  "desc": "termux config (~/.config/termux)",
  "script": "termux.sh",
  "check": "~/.config/termux"
}
```

- `desc` 必填，只写宾语，动词放 `action`
- `action` 主动词（`link` / `symlink` / `install` / `clone` …），TUI 里单独一列对齐；不写默认 `run`
- `check` — symlink 检测（指向 dotfiles → installed，否则 → conflict）
- `check_exists` — 仅存在性检测（用于 cp / 下载模式）
- `check` 和 `check_exists` 二选一，不写则无状态显示
- 路径支持 `~` 与环境变量（如 `$WIN_HOME`）

`check` / `check_exists` 也可写成按平台标签取值的对象，命中当前平台的第一个标签：

```json
"check": { "mac": "~/Library/Rime/cn_dicts", "linux": "~/.config/fcitx5" }
```

可用 `"default"` 作为兜底键。

## os 平台限制

`os` 字段声明模块支持的平台标签，不匹配时该模块在 TUI 中置灰、不可选中，并自动沉到列表底部：

```json
{ "name": "karabiner", "source": "karabiner", "target": "~/.config/karabiner", "os": ["mac"] }
```

平台标签（按优先级从具体到宽泛）：

| 环境 | 标签 |
| --- | --- |
| Termux | `termux` |
| macOS | `mac` |
| WSL | `wsl`, `linux` |
| 其他 Linux | `linux` |

省略 `os` 表示全平台可用。

## 脚本编写规则

- 由 `bash <script>` 执行，cwd 为 `DOTFILES_DIR`
- `$DOTFILES_DIR` 和 `$WIN_HOME`（win 模式）由 setup.py export
- 退出码 `0` 成功，非零失败
- 目标已存在时 `echo "skip: ..."` 并 `exit 0`

## 添加新模块

**纯 symlink**：在 `modules.json` 加一项，写 `name`、`source`、`target`（按需加 `os`）。

**复杂逻辑**：
1. 在 `modules.json` 加一项，写 `name`、`desc`、`script`、`check`/`check_exists`（按需加 `os`）
2. 创建对应 .sh 脚本，实现安装逻辑

## TUI 功能

界面按终端宽高自适应：标题行右侧显示当前平台标签，列表为「标记 · 名称 · 动作 · 描述 · 状态」五列对齐，
描述过长自动截断，底部为按键提示。终端尺寸变化时（SIGWINCH）实时重排，不需要按键触发。

- 标记：`◉` 已选、`○` 未选、`×` 当前平台不可用
- 光标行整行底色高亮（cursorline，`48;5;237`），该行取消 DIM 保证对比度；行尾先 reset 再 `\033[K`，否则底色会漏到屏幕边缘
- 标题分隔线下方一行显示光标行的描述，始终单行截断，不受 wrap 影响
- 列表行默认 nowrap（`…` 截断）；`,vw` 切到 wrap 后描述折行成多行，续行对齐到描述列，cursorline 覆盖该条目的所有行。光标仍按条目移动，视口按屏幕行滚动并保证当前条目完整可见
- 多键序列由 `SEQUENCES` 表驱动（`gg`、`,vw`），前缀键等待 1s 超时，与 nvim 的 `timeoutlen` 同理；`/` 输入过滤时自动关闭，避免吞掉 `,`、`g` 等字符
- 状态列：`● installed` 绿色、`▲ conflict` 黄色、不可用模块显示其 `os` 标签
- 窄终端逐级降级：状态列先缩为单图标、再隐藏动作列、最后隐藏状态列；名称列最多占半行，按键提示同步精简，任何宽度都不折行
- 不可用模块沉到列表底部，用 `unavailable on <tags>` 分隔线分组，且无法选中
- 列表超出屏幕时自动滚动，上下用 `↑ N more` / `↓ N more` 提示
- `j/k` 或方向键移动，`Space` 选择，`Ctrl-D`/`Ctrl-U` 半页，`gg`/`G` 首尾
- `/` 搜索（匹配 name 与 desc，大小写不敏感），`Esc` 清除过滤
- `Enter` 执行，`q` 退出
- 执行时每个模块一条 `── <name> ──` 分隔，结果为 `✓` / `✗ exit N`
- 结尾 summary 复用状态图标并统计成功数；有模块失败时退出码为 1
