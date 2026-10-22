# q-python-install

为 Python 脚本生成 Bash 入口，默认输出到本仓库的 `bin/common`：

```sh
q-python-install /path/project/tool.py
q-python-install /path/project/tool.py -o /path/bin --output-name tool
```

入口根据自身真实位置定位仓库，支持符号链接和显式 `DOTFILES_DIR`。
将入口安装到其它目录时使用符号链接；复制入口后需要在新位置重新生成。

脚本所在目录的 `.script` 会嵌入入口，可声明：

- `TARGET_NAME`：入口名称，`--output-name` 优先。
- `SCRIPT_RUNNER=python3`：纯标准库项目直接使用系统 `python3 -B`，Python 版本需满足项目要求。
- `SCRIPT_EXTRAS`：uv 可选依赖列表，使用空格分隔。

默认 runner 为 uv：普通用户运行时自动同步项目环境和声明的 extras。
root 运行时只执行项目中已有的 `.venv/bin/python`，不会调用 uv；环境缺失时明确报错。
依赖新增或变化后，先以普通用户运行入口，或在项目中执行 `uv sync`（按需加 `--extra`）。
root 使用已有 `.venv` 时会设置 `VIRTUAL_ENV`、将 `.venv/bin` 加入 `PATH`；
所有 root 入口都禁用当前及子 Python 进程的字节码写入。
程序自身创建的配置和输出仍使用运行进程的身份。

验证：

```sh
python3 -m unittest discover -s module/python-install/tests -p 'test_*.py'
```

root 分支测试在 Linux 上使用 `unshare --user --map-root-user`；无法创建用户命名空间时跳过。
