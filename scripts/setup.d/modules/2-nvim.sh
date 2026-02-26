#!/bin/bash
# DESC: link nvim config (~/.config/nvim -> ~/.dotfiles/vim)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.config/nvim"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

mkdir -p "$HOME/.config"
ln -s "$DOTFILES_DIR/vim" "$TARGET"
