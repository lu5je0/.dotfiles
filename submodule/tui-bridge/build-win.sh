#!/usr/bin/env bash
set -euo pipefail

CC="/mnt/c/Users/lu5je0/scoop/apps/gcc/13.2.0/bin/gcc.exe"
OUT="${1:-tui_bridge_win}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIM_LIB_OUT="${SCRIPT_DIR}/../../vim/lib/tui_bridge_win"
SOURCES=(
  "tui-bridge.c"
  "win/im.c"
  "win/clipboard-bridge.c"
  "win/platform.c"
)
CFLAGS=("-O3" "-flto" "-DNDEBUG" "-s" "-Wl,--gc-sections")
LDFLAGS=("-luser32" "-limm32" "-lole32" "-luuid" "-lmsctfmonitor")

sync_to_vim_lib() {
  local built_out="$1"
  if [[ -d "$(dirname "${VIM_LIB_OUT}")" ]]; then
    cp "${built_out}" "${VIM_LIB_OUT}"
  fi
}

if command -v wslpath >/dev/null 2>&1; then
  OUT_BASENAME="$(basename "${OUT}")"
  WIN_TEMP_ROOT="C:\\Users\\lu5je0\\AppData\\Local\\Temp"
  WIN_BUILD_DIR="${WIN_TEMP_ROOT}\\tui-bridge-build"
  WIN_BUILD_DIR_WSL="$(wslpath -u "${WIN_BUILD_DIR}")"

  mkdir -p "$(dirname "${OUT}")"
  mkdir -p "${WIN_BUILD_DIR_WSL}"

  SRC_ARGS=()
  for src in "${SOURCES[@]}"; do
    SRC_ARGS+=("$(wslpath -w "$(pwd)/${src}")")
  done

  (
    cd "${WIN_BUILD_DIR_WSL}"
    "${CC}" "${SRC_ARGS[@]}" -o "${OUT_BASENAME}" "${CFLAGS[@]}" "${LDFLAGS[@]}"
  )
  if [[ -f "${WIN_BUILD_DIR_WSL}/${OUT_BASENAME}" ]]; then
    cp "${WIN_BUILD_DIR_WSL}/${OUT_BASENAME}" "${OUT}"
  else
    cp "${WIN_BUILD_DIR_WSL}/${OUT_BASENAME}.exe" "${OUT}"
  fi
  sync_to_vim_lib "${OUT}"
else
  OUT_ARG="${OUT}"
  SRC_ARGS=("${SOURCES[@]}")
  "${CC}" "${SRC_ARGS[@]}" -o "${OUT_ARG}" "${CFLAGS[@]}" "${LDFLAGS[@]}"
  sync_to_vim_lib "${OUT_ARG}"
fi
