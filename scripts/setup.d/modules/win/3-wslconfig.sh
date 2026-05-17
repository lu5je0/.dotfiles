#!/bin/bash
# DESC: link wslconfig (Windows side symlink)
# CHECK: /mnt/c/Users/lu5je0/.wslconfig

WIN_HOME="${WIN_HOME:-/mnt/c/Users/lu5je0}"
TARGET="$WIN_HOME/.wslconfig"

if [ -e "$TARGET" ]; then
  echo "skip: $TARGET already exists"
  exit 0
fi

/mnt/c/Windows/System32/cmd.exe \
  /c sudo mklink \
  "$(wslpath -w "$TARGET")" \
  "$(wslpath -w "$WIN_HOME/.dotfiles/win/wsl2/wslconfig")"
