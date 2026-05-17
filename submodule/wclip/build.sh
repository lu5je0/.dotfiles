#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

WIN_CC="${WIN_CC:-/mnt/c/Users/lu5je0/scoop/apps/gcc/13.2.0/bin/gcc.exe}"
WIN_TEMP_ROOT="${WIN_TEMP_ROOT:-C:\\Users\\lu5je0\\AppData\\Local\\Temp}"

OUT_DIR="${SCRIPT_DIR}/../../win/bin"
OUT_NAME="wclip"
SRC="wclip.c"
CFLAGS=("-O3" "-flto" "-DNDEBUG" "-s" "-Wl,--gc-sections")
LDFLAGS=("-lshell32")

mkdir -p "${OUT_DIR}"

if command -v wslpath >/dev/null 2>&1; then
  win_build_dir="${WIN_TEMP_ROOT}\\wclip-build"
  win_build_dir_wsl="$(wslpath -u "${win_build_dir}")"
  mkdir -p "${win_build_dir_wsl}"

  win_src="$(wslpath -w "${SCRIPT_DIR}/${SRC}")"

  (
    cd "${win_build_dir_wsl}"
    "${WIN_CC}" "${win_src}" -o "${OUT_NAME}" "${CFLAGS[@]}" "${LDFLAGS[@]}"
  )

  if [[ -f "${win_build_dir_wsl}/${OUT_NAME}" ]]; then
    cp "${win_build_dir_wsl}/${OUT_NAME}" "${OUT_DIR}/${OUT_NAME}"
  else
    cp "${win_build_dir_wsl}/${OUT_NAME}.exe" "${OUT_DIR}/${OUT_NAME}.exe"
  fi
else
  "${WIN_CC}" "${SRC}" -o "${OUT_DIR}/${OUT_NAME}" "${CFLAGS[@]}" "${LDFLAGS[@]}"
fi

echo "Built: ${OUT_DIR}/${OUT_NAME}"
