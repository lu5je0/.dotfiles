#!/bin/bash
# DESC: link IdeaVim config (~/.ideavimrc)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.ideavimrc"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

ln -s "$DOTFILES_DIR/ideavimrc" "$TARGET"
