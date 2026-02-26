#!/bin/bash
# DESC: link zshrc (~/.zshrc)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.zshrc"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

ln -s "$DOTFILES_DIR/zshrc" "$TARGET"
