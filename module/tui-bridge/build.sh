#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

OUT_ARG="${1:-}"

BIN_DIR="${SCRIPT_DIR}/../../bin"
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
        printf 'linux\n'
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

sync_to_bin() {
  local built_out="$1"
  local bin_out="$2"

  if [[ -d "${BIN_DIR}" ]]; then
    mkdir -p "$(dirname "${bin_out}")"
    cp "${built_out}" "${bin_out}.new"
    mv -f "${bin_out}.new" "${bin_out}"
  fi
}

build_linux() {
  local out="${1:-tui-bridge}"
  local gen_dir="${SCRIPT_DIR}/linux/gen"
  local wlr_xml="${SCRIPT_DIR}/linux/protocol/wlr-data-control-unstable-v1.xml"
  local ext_xml="${SCRIPT_DIR}/linux/protocol/ext-data-control-v1.xml"
  local sources=(
    "third_party/cjson/cJSON.c"
    "request-dispatch.c"
    "tui-bridge.c"
    "linux/im.c"
    "linux/clipboard-bridge.c"
    "linux/clipboard-x11.c"
    "linux/platform.c"
    "linux/gen/wlr-data-control-unstable-v1-protocol.c"
    "linux/gen/ext-data-control-v1-protocol.c"
  )
  local cflags=("-O3" "-flto" "-DNDEBUG" "-s" "-Wl,--gc-sections" "-I${gen_dir}")
  local bin_out="${BIN_DIR}/linux-x86_64/tui-bridge"

  mkdir -p "${gen_dir}"
  wayland-scanner client-header "${wlr_xml}" \
    "${gen_dir}/wlr-data-control-unstable-v1-client-protocol.h"
  wayland-scanner private-code "${wlr_xml}" \
    "${gen_dir}/wlr-data-control-unstable-v1-protocol.c"
  wayland-scanner client-header "${ext_xml}" \
    "${gen_dir}/ext-data-control-v1-client-protocol.h"
  wayland-scanner private-code "${ext_xml}" \
    "${gen_dir}/ext-data-control-v1-protocol.c"

  gcc "${sources[@]}" -o "${out}" "${cflags[@]}" \
    $(pkg-config --cflags --libs dbus-1 wayland-client x11) -lpthread
  sync_to_bin "${out}" "${bin_out}"
}

build_mac() {
  local out="${1:-tui-bridge}"
  local sources=(
    "third_party/cjson/cJSON.c"
    "request-dispatch.c"
    "tui-bridge.c"
    "mac/im.m"
    "mac/clipboard-bridge.m"
    "mac/platform.c"
  )
  local cflags=("-O3" "-flto" "-DNDEBUG" "-fobjc-arc" "-Wl,-dead_strip")
  local ldflags=("-framework" "Carbon" "-framework" "AppKit")
  local bin_out="${BIN_DIR}/macos-arm64/tui-bridge"

  clang "${sources[@]}" -o "${out}" "${cflags[@]}" "${ldflags[@]}"
  sync_to_bin "${out}" "${bin_out}"
}

build_win() {
  local out="${1:-tui-bridge}"
  local out_basename
  local out_dir
  local bin_out="${BIN_DIR}/windows-x86_64/tui-bridge"
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

  local built
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
    built="${out}"
  else
    "${WIN_CC}" "${sources[@]}" -o "${out}.exe" "${cflags[@]}" "${ldflags[@]}"
    built="${out}.exe"
  fi

  if [[ ! -f "${built}" ]]; then
    echo "build_win: expected output '${built}' not found after build" >&2
    exit 1
  fi

  sync_to_bin "${built}" "${bin_out}"
}

TARGET="$(detect_target)"

case "${TARGET}" in
  mac)
    build_mac "${OUT_ARG:-tui-bridge}"
    ;;
  win)
    build_win "${OUT_ARG:-tui-bridge}"
    ;;
  linux)
    build_linux "${OUT_ARG:-tui-bridge}"
    ;;
  *)
    echo "Unsupported platform for auto build: ${TARGET}" >&2
    echo "Usage: ./build.sh [output]" >&2
    exit 1
    ;;
esac
