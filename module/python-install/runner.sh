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

# SCRIPT_EXTRAS：可选的 uv extra 列表（空格分隔）。
# uv run 只会同步项目的基础依赖，平台相关的可选依赖必须显式 --extra 带上，
# 否则新建/重建的隔离环境会缺包。
extra_args=()
for extra in ${SCRIPT_EXTRAS:-}; do
  extra_args+=(--extra "$extra")
done

exec uv run --project "$SCRIPT_PATH" "${extra_args[@]}" "${SCRIPT_PATH}/${SCRIPT_NAME}" "$@"
