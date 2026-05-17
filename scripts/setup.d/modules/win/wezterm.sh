#!/bin/bash

TARGET="$WIN_HOME/.config/wezterm"

if [ -e "$TARGET" ]; then
  echo "skip: $TARGET already exists"
  exit 0
fi

mkdir -p "$WIN_HOME/.config"

/mnt/c/Windows/System32/cmd.exe \
  /c sudo mklink /J \
  "$(wslpath -w "$TARGET")" \
  "$(wslpath -w "$DOTFILES_DIR/wezterm")"
