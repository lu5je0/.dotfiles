#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

OUT="${1:-tui_bridge}"
SOURCES=(
    "tui-bridge.c"
    "mac/im.m"
    "mac/clipboard-bridge.c"
    "mac/platform.c"
)
CFLAGS=("-O3" "-flto" "-DNDEBUG" "-Wl,-dead_strip")
LDFLAGS=("-framework" "Carbon" "-framework" "AppKit")

clang "${SOURCES[@]}" -o "${OUT}" "${CFLAGS[@]}" "${LDFLAGS[@]}"
cp tui_bridge ~/.dotfiles/vim/lib/tui_bridge_mac
