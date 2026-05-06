#!/bin/bash
# DESC: link yazi config (~/.config/yazi)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET_DIR="$HOME/.config/yazi"

if [[ -e "$TARGET_DIR" ]]; then
  echo "skip: $TARGET_DIR exists"
  exit 0
fi

mkdir -p "$HOME/.config"
ln -s "$DOTFILES_DIR/yazi" "$TARGET_DIR"
