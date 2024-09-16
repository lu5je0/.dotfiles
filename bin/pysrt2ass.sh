#!/bin/bash

# 获取当前脚本所在目录
script_dir=/home/lu5je0/.dotfiles/submodule/pysrt2ass

# 虚拟环境中的 Python 解释器路径
venv_python="$script_dir/.env/bin/python"

# 检查虚拟环境是否存在
if [ -x "$venv_python" ]; then
    # 使用 exec 替换当前进程为虚拟环境中的 Python 解释器，传递所有参数
    exec "$venv_python" ${script_dir}/pysrt2ass.py "$@"
else
    echo "Error: venv environment not found." >&2
    exit 1
fi
