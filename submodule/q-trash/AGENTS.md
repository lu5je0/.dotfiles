# q-trash 工作指引

## 适用范围
- 本文件适用于 `submodule/q-trash/` 目录。

## 组件职责
- `q-rm.py`：rm 兼容的命令行入口，把文件移动到 freedesktop.org Trash Spec 1.0 回收站。
  - 严格按 spec：文件只进入它所在卷的回收站；不做跨卷拷贝，找不到合适 trash 目录时报错。
  - WSL 下 Windows 原生路径走 PowerShell 回收站；macOS 走系统 `trash` 命令。
  - 与 trash-cli 互通：`trash-list` 能列、`trash-restore --trash-dir=...` 能恢复。
- `q-trash.py`：管理回收站本身（`list` / `restore` / `empty` / `size` / `rm`）。
  - 通过 importlib 复用 `q-rm.py` 的 `is_safe_top_trash`、`home_trash_dir`、`_read_mount_fstype_map`，避免重复实现。
  - 扫描 `$top/.Trash/$UID` 时遵循 reader 端的 sticky-bit 检查，与 q-rm 写入端一致。
- `tests/run_compare.py`：与系统 `rm` 行为对照。
- `tests/run_qtrash.py`：q-trash 的端到端测试。

## 目录协作规则
- 仅用 Python 3 标准库，避免 uv 等启动开销（`rm` 调用频繁）。
- 入口符号链接位于根目录 `bin/q-rm`、`bin/q-trash`，分别指向本目录的 `q-rm.py`、`q-trash.py`。
- 调整 CLI 时同步检查根目录 `bin/` 链接、`zsh/completions/_q-rm`、`zsh/completions/_q-trash` 与 README。
- 不在本目录重复记录根仓库的通用约定。

## 验证原则
- 修改后至少执行语法检查：`python3 -m py_compile q-rm.py q-trash.py`。
- 涉及 trashinfo 格式或回收站定位时，需用 `trash-list` 验证互通。
- 改动 q-rm CLI 行为后跑 `python3 tests/run_compare.py`（与系统 `rm` 对照，无需 pytest）。
- 改动 q-trash 行为后跑 `python3 tests/run_qtrash.py`。
