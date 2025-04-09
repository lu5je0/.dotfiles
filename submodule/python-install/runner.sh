#!/bin/bash

# 获取当前脚本所在目录
if [ -z $SCRIPT_PATH ]; then
  echo 'SCRIPT_PATH is empty'
  return -1
fi

if [ -z $SCRIPT_NAME ]; then
  echo 'SCRIPT_NAME is empty'
  return -1
fi

ask() {
    echo -n $1
    echo -n $' (y/n) \\n# '
    read choice
    case $choice in
        Y | y)
        return 0
    esac
    return -1
}

# 从 .script 文件中读取配置
if [ -f "$SCRIPT_PATH/.script" ]; then
    source "$SCRIPT_PATH/.script"
fi

# 检查是否定义了 VENV_DIR
if [ -n "$VENV_DIR" ]; then
    # 虚拟环境目录
    venv_dir="$SCRIPT_PATH/$VENV_DIR"

    # 虚拟环境中的 Python 解释器路径
    venv_python="$venv_dir/bin/python"

    # 检查并创建虚拟环境
    if [ ! -d "$venv_dir" ]; then
        if ask "Virtual environment does not exist. Do you want to create it?"; then
            echo "Creating virtual environment..."
            python3 -m venv "$venv_dir"
            # 安装依赖
            if [ -f "$SCRIPT_PATH/requirements.txt" ]; then
                echo "Installing dependencies..."
                "$venv_python" -m pip install -r "$SCRIPT_PATH/requirements.txt"
            fi
        fi
        
        exit 1
    fi

    # 使用 exec 替换当前进程为虚拟环境中的 Python 解释器，传递所有参数
    exec "$venv_python" ${SCRIPT_PATH}/${SCRIPT_NAME} "$@"
else
    # 如果没有定义 VENV_DIR，直接使用系统 Python 运行脚本
    exec python3 ${SCRIPT_PATH}/${SCRIPT_NAME} "$@"
fi
