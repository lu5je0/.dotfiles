#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

OUT_ARG="${1:-}"

VIM_LIB_DIR="${SCRIPT_DIR}/../../vim/lib"
WIN_CC="${WIN_CC:-/mnt/c/Users/lu5je0/scoop/apps/gcc/13.2.0/bin/gcc.exe}"
WIN_TEMP_ROOT="${WIN_TEMP_ROOT:-C:\\Users\\lu5je0\\AppData\\Local\\Temp}"

detect_target() {
  case "$(uname -s)" in
    Darwin)
      printf 'mac\n'
      ;;
    Linux)
      if command -v wslpath >/dev/null 2>&1; then
        printf 'win\n'
      else
        printf 'unsupported\n'
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      printf 'win\n'
      ;;
    *)
      printf 'unsupported\n'
      ;;
  esac
}

sync_to_vim_lib() {
  local built_out="$1"
  local vim_lib_out="$2"

  if [[ -d "${VIM_LIB_DIR}" ]]; then
    mkdir -p "$(dirname "${vim_lib_out}")"
    cp "${built_out}" "${vim_lib_out}"
  fi
}

build_mac() {
  local out="${1:-tui_bridge}"
  local sources=(
    "third_party/cjson/cJSON.c"
    "request-dispatch.c"
    "tui-bridge.c"
    "mac/im.m"
    "mac/clipboard-bridge.c"
    "mac/platform.c"
  )
  local cflags=("-O3" "-flto" "-DNDEBUG" "-Wl,-dead_strip")
  local ldflags=("-framework" "Carbon" "-framework" "AppKit")
  local vim_lib_out="${VIM_LIB_DIR}/macos/bin/tui_bridge"

  clang "${sources[@]}" -o "${out}" "${cflags[@]}" "${ldflags[@]}"
  sync_to_vim_lib "${out}" "${vim_lib_out}"
}

build_win() {
  local out="${1:-tui_bridge}"
  local out_basename
  local out_dir
  local vim_lib_out="${VIM_LIB_DIR}/windows/bin/tui_bridge"
  local sources=(
    "third_party/cjson/cJSON.c"
    "request-dispatch.c"
    "tui-bridge.c"
    "win/im.c"
    "win/clipboard-bridge.c"
    "win/platform.c"
  )
  local cflags=("-O3" "-flto" "-DNDEBUG" "-s" "-Wl,--gc-sections")
  local ldflags=("-luser32" "-limm32" "-lole32" "-luuid" "-lmsctfmonitor")

  out_basename="$(basename "${out}")"
  out_dir="$(dirname "${out}")"
  mkdir -p "${out_dir}"

  if command -v wslpath >/dev/null 2>&1; then
    local win_build_dir="${WIN_TEMP_ROOT}\\tui-bridge-build"
    local win_build_dir_wsl
    local src_args=()
    local src

    win_build_dir_wsl="$(wslpath -u "${win_build_dir}")"
    mkdir -p "${win_build_dir_wsl}"

    for src in "${sources[@]}"; do
      src_args+=("$(wslpath -w "${SCRIPT_DIR}/${src}")")
    done

    (
      cd "${win_build_dir_wsl}"
      "${WIN_CC}" "${src_args[@]}" -o "${out_basename}" "${cflags[@]}" "${ldflags[@]}"
    )

    if [[ -f "${win_build_dir_wsl}/${out_basename}" ]]; then
      cp "${win_build_dir_wsl}/${out_basename}" "${out}"
    else
      cp "${win_build_dir_wsl}/${out_basename}.exe" "${out}"
    fi
  else
    "${WIN_CC}" "${sources[@]}" -o "${out}" "${cflags[@]}" "${ldflags[@]}"
  fi

  sync_to_vim_lib "${out}" "${vim_lib_out}"
}

TARGET="$(detect_target)"

case "${TARGET}" in
  mac)
    build_mac "${OUT_ARG:-tui_bridge}"
    ;;
  win)
    build_win "${OUT_ARG:-tui_bridge}"
    ;;
  *)
    echo "Unsupported platform for auto build: ${TARGET}" >&2
    echo "Usage: ./build.sh [output]" >&2
    exit 1
    ;;
esac
