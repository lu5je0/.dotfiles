# Setup Modules 工作指引

## 概览

`scripts/setup.sh` 是 dotfiles 安装入口，提供 TUI 多选菜单，按模块执行安装。模块按平台分目录存放：

- `modules/unix/` — macOS / Linux / WSL（从 WSL 内部视角）
- `modules/win/` — WSL 环境且 dotfiles 位于 `/mnt/c/` 时，操作 Windows 侧文件

平台自动识别：WSL + `DOTFILES_DIR` 在 `/mnt/c/*` 时加载 `win/`，否则加载 `unix/`。

## 模块文件约定

每个模块是独立的 bash 脚本，文件名格式 `<数字>-<名称>.sh`，数字决定排序。

### 必须包含的注释头

```bash
#!/bin/bash
# DESC: <一句话描述，显示在 TUI 菜单中>
# CHECK: <检测路径>
```

- `# DESC:` — 必填。TUI 菜单中显示的模块描述。
- `# CHECK: <path>` — 用于 symlink 检测。路径存在且是指向 `$DOTFILES_DIR` 的 symlink → 显示 `(installed)`；路径存在但不是 dotfiles symlink → 显示 `(conflict)`；路径不存在 → 无标记。支持 `~` 展开。
- `# CHECK_EXISTS: <path>` — 仅检测路径是否存在（用于 `cp` 等非 symlink 安装方式）。存在 → `(installed)`，不存在 → 无标记。

`# CHECK:` 和 `# CHECK_EXISTS:` 二选一，没有则 TUI 不显示状态。

### 模块编写规则

- 模块由 `bash "$module_file"` 执行，运行在子 shell 中。
- `$DOTFILES_DIR` 由父脚本 export，模块内可直接使用，也应提供 fallback：`DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"`。
- 退出码 `0` 表示成功，非零表示失败，父脚本会据此打印 OK/FAIL。
- 如果目标已存在，通常 `echo "skip: ..."` 并 `exit 0`。
- unix 模块一般用 `ln -s` 创建 symlink，win 模块通过 `cmd.exe /c sudo mklink` 创建 Windows 侧 symlink。

## 添加新模块

1. 在对应平台目录下创建 `<序号>-<名称>.sh`。
2. 写入 `#!/bin/bash`、`# DESC:` 和 `# CHECK:`（或 `# CHECK_EXISTS:`）。
3. 实现安装逻辑，处理目标已存在的情况。

示例（symlink 模式）：

```bash
#!/bin/bash
# DESC: link foo config (~/.config/foo)?
# CHECK: ~/.config/foo

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.config/foo"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

mkdir -p "$HOME/.config"
ln -s "$DOTFILES_DIR/foo" "$TARGET"
```

示例（copy 模式）：

```bash
#!/bin/bash
# DESC: copy bar config (~/.bar)?
# CHECK_EXISTS: ~/.bar

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
cp -i "$DOTFILES_DIR/bar" "$HOME/.bar"
```
