#!/bin/bash
# DESC: link Ghostty config (~/.config/ghostty)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.config/ghostty"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

mkdir -p "$HOME/.config"
ln -s "$DOTFILES_DIR/ghostty" "$TARGET"
