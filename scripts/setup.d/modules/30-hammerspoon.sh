#!/bin/bash
# DESC: link Hammerspoon config (~/.hammerspoon)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.hammerspoon"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

ln -s "$DOTFILES_DIR/hammerspoon" "$TARGET"
