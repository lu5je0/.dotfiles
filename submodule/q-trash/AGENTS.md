# q-rm 工作指引

## 适用范围
- 本文件适用于 `submodule/q-trash/` 目录。

## 组件职责
- `q-rm.py` 是该目录的主入口，提供 rm 兼容的命令行参数，把文件移动到 freedesktop.org Trash Spec 1.0 回收站。
- 实现严格按 spec：文件只进入它所在卷的回收站；不做跨卷拷贝，找不到合适 trash 目录时报错。
- 与 trash-cli 互通：`trash-list` 能列出、`trash-restore --trash-dir=...` 能恢复。

## 目录协作规则
- 主入口是 `q-rm.py`，使用 Python 3 标准库，避免 uv 等启动开销（`rm` 调用频繁）。根目录 `bin/q-rm` 直接 `exec python3` 调用。
- 如果调整 `q-rm.py` 的 CLI 参数，需要同步检查根目录 `bin/q-rm` 包装脚本以及 README。
- 不要在本目录重复记录根仓库的通用约定；这里只记录 `q-rm` 自身的职责和联动关系。

## 验证原则
- 修改后至少执行语法检查：`python3 -m py_compile q-rm.py`。
- 如果改动涉及 trashinfo 格式或回收站定位，需用 `trash-list` 验证互通。
- 改动 CLI 行为后跑 `python3 tests/run_compare.py`（与系统 `rm` 行为对照，无需 pytest）。
- pytest 测试位于 `tests/test_qrm.py`：`python3 -m pytest tests/`（环境内若无 pytest 可跳过，以对比测试为准）。
