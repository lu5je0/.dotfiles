# Setup Modules 工作指引

## 概览

`setup.sh`（仓库根目录）是 dotfiles 安装入口，提供 TUI 多选菜单，按模块执行安装。

模块按平台分目录存放在 `scripts/setup.d/modules/` 下：

- `unix/` — macOS / Linux / WSL（从 WSL 内部视角）
- `win/` — WSL 环境且 dotfiles 位于 `/mnt/c/` 时，操作 Windows 侧文件

平台自动识别：WSL + `DOTFILES_DIR` 在 `/mnt/c/*` 时加载 `win/`，否则加载 `unix/`。

## modules.conf

每个平台目录下有一个 `modules.conf`，INI 风格，声明所有模块。每个 `[section]` 是一个模块。

### LINK 模块

纯 symlink，无需 .sh 脚本：

```ini
[kitty]
link = kitty -> ~/.config/kitty
```

- `desc` 可选，省略时自动生成 `link ./<source> -> <target>`
- check 自动从 target 推导（symlink 指向 dotfiles → installed）
- setup.sh 自动处理 mkdir、ln -s、skip

### SCRIPT 模块

复杂逻辑（多文件、cp、下载等），指向同目录下的 .sh 脚本：

```ini
[termux]
desc = link termux config (~/.config/termux) + download Nerd Font
script = termux.sh
check = ~/.config/termux
```

- `desc` 必填
- `check = <path>` — symlink 检测（指向 dotfiles → installed，否则 → conflict）
- `check_exists = <path>` — 仅存在性检测（用于 cp 模式）
- `check` 和 `check_exists` 二选一，不写则无状态显示
- 路径支持 `~` 和 `$WIN_HOME` 等变量展开

## 脚本编写规则

- 由 `bash "$script"` 执行，运行在子 shell
- `$DOTFILES_DIR` 和 `$WIN_HOME`（win 模式）由 setup.sh export
- 退出码 `0` 成功，非零失败
- 目标已存在时 `echo "skip: ..."` 并 `exit 0`
- 脚本内不需要 `# DESC:` 或 `# CHECK:` 注释，这些信息在 conf 中声明

## 添加新模块

**纯 symlink**：在 `modules.conf` 加一个 section，写 `link = ...` 即可。

**复杂逻辑**：
1. 在 `modules.conf` 加 section，写 `desc`、`script`、`check`/`check_exists`
2. 创建对应 .sh 脚本，实现安装逻辑

## TUI 功能

- 状态徽标：`(installed)` 绿色、`(conflict)` 黄色
- `/` 搜索，`n` 跳转下一个匹配（大小写不敏感）
- 执行完成后自动刷新状态，显示 Final Status 汇总
- 底部显示选中计数 `(N/M selected)`
