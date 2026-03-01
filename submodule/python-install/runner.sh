#!/bin/bash

# 获取当前脚本所在目录
if [ -z "$SCRIPT_PATH" ]; then
  echo 'SCRIPT_PATH is empty'
  return -1
fi

if [ -z "$SCRIPT_NAME" ]; then
  echo 'SCRIPT_NAME is empty'
  return -1
fi

ensure_uv() {
    if ! command -v uv >/dev/null 2>&1; then
        echo "Error: uv is required but not found in PATH."
        echo "Install uv first: https://docs.astral.sh/uv/"
        exit 1
    fi
}

ensure_uv
exec uv run --project "$SCRIPT_PATH" --python python3 "${SCRIPT_PATH}/${SCRIPT_NAME}" "$@"
