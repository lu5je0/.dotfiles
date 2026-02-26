#!/bin/bash
# DESC: link bin to ~/.local/bin/solid?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.local/bin/solid"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

mkdir -p "$HOME/.local/bin"
ln -s "$DOTFILES_DIR/bin" "$TARGET"
