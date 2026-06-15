#!/bin/bash

TARGET="$WIN_HOME/AppData/Roaming/neovide/config.toml"

mkdir -p "$(dirname "$TARGET")"

if [ -e "$TARGET" ]; then
  echo "skip: $TARGET already exists"
  exit 0
fi

/mnt/c/Windows/System32/cmd.exe \
  /c sudo mklink \
  "$(wslpath -w "$TARGET")" \
  "$(wslpath -w "$DOTFILES_DIR/win/neovide/config.toml")"
