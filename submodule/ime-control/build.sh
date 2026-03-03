#!/usr/bin/env sh
set -eu

uname_s="$(uname -s)"

if [ "$uname_s" = "Darwin" ]; then
  clang ime_control.c -o ime_control -O2 -framework Carbon -framework CoreFoundation
  exit 0
fi

if [ "${OS:-}" = "Windows_NT" ] || [ "$uname_s" = "MINGW64_NT" ] || [ "$uname_s" = "MSYS_NT" ] || [ "$uname_s" = "CYGWIN_NT" ]; then
  gcc ime_control.c -o ime_control.exe -Os -s -Wl,--gc-sections -luser32 -limm32
  exit 0
fi

if command -v gcc.exe >/dev/null 2>&1; then
  gcc.exe ime_control.c -o ime_control.exe -Os -s -Wl,--gc-sections -luser32 -limm32
  exit 0
fi

if [ -x /mnt/c/Users/lu5je0/scoop/apps/gcc/13.2.0/bin/gcc.exe ]; then
  /mnt/c/Users/lu5je0/scoop/apps/gcc/13.2.0/bin/gcc.exe ime_control.c -o ime_control.exe -Os -s -Wl,--gc-sections -luser32 -limm32
  exit 0
fi

echo "Unsupported build environment: $uname_s (only macOS/Windows/WSL are supported)" >&2
exit 1
