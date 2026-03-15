#!/bin/bash
# DESC: link WezTerm config (~/.config/wezterm)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.config/wezterm"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
  exit 0
fi

mkdir -p "$HOME/.config"
ln -s "$DOTFILES_DIR/wezterm" "$TARGET"
