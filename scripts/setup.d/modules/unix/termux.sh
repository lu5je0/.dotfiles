#!/bin/bash

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.config/termux"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
else
  mkdir -p "$HOME/.config"
  ln -s "$DOTFILES_DIR/termux" "$TARGET"
fi
