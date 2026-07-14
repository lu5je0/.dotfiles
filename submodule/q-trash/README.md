# q-rm

`rm` 兼容的命令行工具，把文件移动到 freedesktop.org 回收站。

## 特性

- **rm 兼容**：参数 `-f -i -I -r -R -d -v --interactive --preserve-root --no-preserve-root --one-file-system --` 行为对齐 GNU `rm`。
- **严格按 Trash Spec 1.0 实现**，与 [trash-cli](https://github.com/andreafrancia/trash-cli) 互通：用 `trash-list` 能列出，用 `trash-restore --trash-dir=...` 能恢复。
- **不做跨卷拷贝**：文件只会进入它所在卷的回收站；找不到合适的 trash 目录就报错，由用户决定是否 `--purge`。
- **纯标准库**，无运行时依赖。

## 回收站位置（按平台）

- **Linux**：按 Trash Spec
  - 文件与 `$HOME` 同卷 → `$XDG_DATA_HOME/Trash`（默认 `~/.local/share/Trash`），`Path=` 写绝对路径
  - 文件在其他挂载点 → 优先 `$top/.Trash/$UID`（要求 sticky + 非 symlink），否则 `$top/.Trash-$UID`，`Path=` 写**相对该挂载点**的路径
- **WSL**：路径在 Windows 原生盘（`drvfs` / `9p` / `virtiofs` 挂载，例如 `/mnt/c/...`）→ 走 **Windows 回收站**（PowerShell + `Microsoft.VisualBasic.FileIO`），可在 Windows 资源管理器还原。Linux 侧路径仍按上面的 Trash Spec。
- **macOS**：通过 ctypes 调用系统 Foundation API（`NSFileManager trashItemAtURL:`），无需第三方 `trash` 命令，put-back 记录由系统写入。

不做跨卷拷贝。Linux 下找不到合适 trash 目录就报错，提示 `--purge`。

## 用法

```sh
q-rm file
q-rm -rf dir
q-rm --purge file        # 真删，绕过回收站
```

恢复：

```sh
trash-restore --trash-dir=/mnt/c/.Trash-1000     # 卷上回收站
trash-restore --trash-dir=~/.local/share/Trash   # home 回收站
```

> 备注：`trash-restore` 在 WSL2 不带 `--trash-dir` 时无法识别 `virtiofs` 挂载点（trash-cli 上游 bug，白名单缺 `virtiofs`），所以 WSL2 下要用 `--trash-dir`。

## alias 为 rm

自行决定是否在 shell 配置里：

```sh
alias rm='q-rm'
```
