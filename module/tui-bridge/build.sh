#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  echo "Usage: ./build.sh [output]"
  echo "Build for the current platform (WSL builds Windows); default: build/tui-bridge[.exe]"
  exit 0
fi
if [[ $# -gt 1 || "${1:-}" == -* ]]; then
  echo "Usage: ./build.sh [output]" >&2
  exit 1
fi
OUT_ARG="${1:-}"
VERSION="$(cat VERSION)"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid VERSION: ${VERSION}" >&2
  exit 1
fi
VERSION_FLAG="-DTUI_BRIDGE_VERSION=\"${VERSION}\""

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

  mkdir -p "${gen_dir}"
  wayland-scanner client-header "${wlr_xml}" \
    "${gen_dir}/wlr-data-control-unstable-v1-client-protocol.h"
  wayland-scanner private-code "${wlr_xml}" \
    "${gen_dir}/wlr-data-control-unstable-v1-protocol.c"
  wayland-scanner client-header "${ext_xml}" \
    "${gen_dir}/ext-data-control-v1-client-protocol.h"
  wayland-scanner private-code "${ext_xml}" \
    "${gen_dir}/ext-data-control-v1-protocol.c"

  gcc "${sources[@]}" -o "${out}" "${VERSION_FLAG}" "${cflags[@]}" \
    $(pkg-config --cflags --libs dbus-1 wayland-client x11) -lpthread
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
  clang "${sources[@]}" -o "${out}" "${VERSION_FLAG}" "${cflags[@]}" "${ldflags[@]}"
}

build_win() {
  local out="${1:-tui-bridge}"
  local out_basename
  local out_dir
  local sources=(
    "third_party/cjson/cJSON.c"
    "request-dispatch.c"
    "tui-bridge.c"
    "win/im.c"
    "win/clipboard-bridge.c"
    "win/platform.c"
  )
  local cflags=("-O3" "-flto" "-DNDEBUG" "-s" "-static" "-Wl,--gc-sections")
  local ldflags=("-luser32" "-limm32" "-lole32" "-luuid" "-lmsctfmonitor")

  out_basename="$(basename "${out}")"
  out_dir="$(dirname "${out}")"
  mkdir -p "${out_dir}"

  local built
  if command -v wslpath >/dev/null 2>&1; then
    local win_build_dir_wsl
    local win_temp_root="${WIN_TEMP_ROOT:-$(cmd.exe /c echo %TEMP% | tr -d '\r')}"
    local src_args=()
    local src

    win_build_dir_wsl="$(mktemp -d "$(wslpath -u "${win_temp_root}")/tui-bridge.XXXXXX")"

    for src in "${sources[@]}"; do
      src_args+=("$(wslpath -w "${SCRIPT_DIR}/${src}")")
    done

    (
      cd "${win_build_dir_wsl}"
      "${WIN_CC:-gcc.exe}" "${src_args[@]}" -o "${out_basename}" "${VERSION_FLAG}" "${cflags[@]}" "${ldflags[@]}"
    )

    if [[ -f "${win_build_dir_wsl}/${out_basename}" ]]; then
      cp "${win_build_dir_wsl}/${out_basename}" "${out}"
    else
      cp "${win_build_dir_wsl}/${out_basename}.exe" "${out}"
    fi
    built="${out}"
    rm -rf "${win_build_dir_wsl}"
  else
    "${WIN_CC:-gcc}" "${sources[@]}" -o "${out}" "${VERSION_FLAG}" "${cflags[@]}" "${ldflags[@]}"
    built="${out}"
  fi

  if [[ ! -f "${built}" ]]; then
    echo "build_win: expected output '${built}' not found after build" >&2
    exit 1
  fi
}

TARGET="$(detect_target)"
if [[ -z "${OUT_ARG}" ]]; then
  OUT_ARG="build/tui-bridge"
  if [[ "${TARGET}" == win ]]; then
    OUT_ARG+=".exe"
  fi
fi
mkdir -p "$(dirname "${OUT_ARG}")"

case "${TARGET}" in
  mac)
    build_mac "${OUT_ARG}"
    ;;
  win)
    build_win "${OUT_ARG}"
    ;;
  linux)
    build_linux "${OUT_ARG}"
    ;;
  *)
    echo "Unsupported platform for auto build: ${TARGET}" >&2
    echo "Usage: ./build.sh [output]" >&2
    exit 1
    ;;
esac
