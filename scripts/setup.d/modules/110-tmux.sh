#!/bin/bash
# DESC: link tmux config (~/.config/tmux)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.config/tmux"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

mkdir -p "$HOME/.config"
ln -s "$DOTFILES_DIR/tmux" "$TARGET"
