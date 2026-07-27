#!/bin/bash

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.m2/settings.xml"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

mkdir -p "$(dirname "$TARGET")"
cp "$DOTFILES_DIR/m2/settings.xml" "$TARGET"
