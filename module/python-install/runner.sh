#!/bin/bash

if [ -z "${SCRIPT_PATH:-}" ]; then
  echo 'SCRIPT_PATH is empty' >&2
  return 1
fi

if [ -z "${SCRIPT_NAME:-}" ]; then
  echo 'SCRIPT_NAME is empty' >&2
  return 1
fi

# 包括脚本启动的子 Python 进程，root 都不向源码或用户环境写入字节码。
if (( EUID == 0 )); then
  export PYTHONDONTWRITEBYTECODE=1
fi

# 纯标准库项目通过 .script 声明 SCRIPT_RUNNER=python3，默认使用 uv。
case ${SCRIPT_RUNNER:-uv} in
  python3)
    if ! command -v python3 >/dev/null 2>&1; then
      echo 'Error: python3 is required but not found in PATH.' >&2
      exit 1
    fi
    exec python3 -B "${SCRIPT_PATH}/${SCRIPT_NAME}" "$@"
    ;;
  uv) ;;
  *)
    printf 'Error: unknown SCRIPT_RUNNER: %s\n' "$SCRIPT_RUNNER" >&2
    exit 1
    ;;
esac

# root 只运行普通用户准备的解释器，不通过 uv 同步 .venv、uv.lock 或缓存。
if (( EUID == 0 )); then
  venv_dir="$SCRIPT_PATH/.venv"
  if [ ! -x "$venv_dir/bin/python" ]; then
    printf 'Error: prepared Python environment not found: %s\n' "$venv_dir" >&2
    printf 'Prepare dependencies as your regular user before running with sudo.\n' >&2
    exit 1
  fi
  export VIRTUAL_ENV="$venv_dir"
  export PATH="$venv_dir/bin:$PATH"
  exec "$venv_dir/bin/python" -B "${SCRIPT_PATH}/${SCRIPT_NAME}" "$@"
fi

if ! command -v uv >/dev/null 2>&1; then
  echo 'Error: uv is required but not found in PATH.' >&2
  echo 'Install uv first: https://docs.astral.sh/uv/' >&2
  exit 1
fi

# SCRIPT_EXTRAS：可选的 uv extra 列表（空格分隔）。
# uv run 只会同步项目的基础依赖，平台相关的可选依赖必须显式 --extra 带上，
# 否则新建/重建的隔离环境会缺包。
extra_args=()
for extra in ${SCRIPT_EXTRAS:-}; do
  extra_args+=(--extra "$extra")
done

exec uv run --project "$SCRIPT_PATH" "${extra_args[@]}" "${SCRIPT_PATH}/${SCRIPT_NAME}" "$@"
