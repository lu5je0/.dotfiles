#!/bin/bash

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.local/bin/q-trash"

if [[ -L "$TARGET" ]]; then
  echo "skip: $TARGET already linked"
  exit 0
fi

mkdir -p "$(dirname "$TARGET")"
ln -sf "$DOTFILES_DIR/submodule/q-trash/q-trash.py" "$TARGET"
