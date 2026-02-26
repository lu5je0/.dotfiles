#!/bin/bash
# DESC: link cheat dir (~/.cheat)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.cheat"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

ln -s "$DOTFILES_DIR/cheat" "$TARGET"
