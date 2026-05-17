#!/bin/bash
# DESC: link WezTerm config (Windows side junction)
# CHECK: /mnt/c/Users/lu5je0/.config/wezterm

WIN_HOME="${WIN_HOME:-/mnt/c/Users/lu5je0}"
TARGET="$WIN_HOME/.config/wezterm"

if [ -e "$TARGET" ]; then
  echo "skip: $TARGET already exists"
  exit 0
fi

mkdir -p "$WIN_HOME/.config"

/mnt/c/Windows/System32/cmd.exe \
  /c sudo mklink /J \
  "$(wslpath -w "$TARGET")" \
  "$(wslpath -w "$WIN_HOME/.dotfiles/wezterm")"
