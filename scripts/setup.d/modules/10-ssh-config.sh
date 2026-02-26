#!/bin/bash
# DESC: link ssh config (~/.ssh/config)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.ssh/config"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

mkdir -p "$HOME/.ssh"
ln -s "$DOTFILES_DIR/ssh/config" "$TARGET"
