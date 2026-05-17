#!/bin/bash
# DESC: link git config (~/.config/git)?
# CHECK: ~/.config/git

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.config/git"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

mkdir -p "$HOME/.config"
ln -s "$DOTFILES_DIR/git" "$TARGET"
