#!/usr/bin/env bash
set -euo pipefail

CC="/mnt/c/Users/lu5je0/scoop/apps/gcc/13.2.0/bin/gcc.exe"
OUT="${1:-tui_bridge_win.exe}"
SOURCES=(
  "tui-bridge.c"
  "win/im.c"
  "win/clipboard-bridge.c"
  "win/platform.c"
)
CFLAGS=("-O3" "-flto" "-DNDEBUG" "-s" "-Wl,--gc-sections")
LDFLAGS=("-luser32" "-limm32")

if command -v wslpath >/dev/null 2>&1; then
  OUT_ARG="$(wslpath -w "$(pwd)/${OUT}")"
  SRC_ARGS=()
  for src in "${SOURCES[@]}"; do
    SRC_ARGS+=("$(wslpath -w "$(pwd)/${src}")")
  done
else
  OUT_ARG="${OUT}"
  SRC_ARGS=("${SOURCES[@]}")
fi

"${CC}" "${SRC_ARGS[@]}" -o "${OUT_ARG}" "${CFLAGS[@]}" "${LDFLAGS[@]}"
