#!/bin/bash

TARGET="$WIN_HOME/.wslconfig"

if [ -e "$TARGET" ]; then
  echo "skip: $TARGET already exists"
  exit 0
fi

/mnt/c/Windows/System32/cmd.exe \
  /c sudo mklink \
  "$(wslpath -w "$TARGET")" \
  "$(wslpath -w "$DOTFILES_DIR/win/wsl2/wslconfig")"
