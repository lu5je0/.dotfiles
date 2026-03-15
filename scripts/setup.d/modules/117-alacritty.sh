#!/bin/bash
# DESC: link Alacritty config (~/.config/alacritty)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET_DIR="$HOME/.config/alacritty"

if [[ -e "$TARGET_DIR/alacritty.toml" || -e "$TARGET_DIR/common.toml" ]]; then
  echo "skip: $TARGET_DIR already configured"
  exit 0
fi

mkdir -p "$TARGET_DIR"
ln -s "$DOTFILES_DIR/alacritty/common.toml" "$TARGET_DIR/common.toml"

if [[ "$(uname)" = "Darwin" ]]; then
  SOURCE_FILE="$DOTFILES_DIR/alacritty/mac.toml"
else
  SOURCE_FILE="$DOTFILES_DIR/alacritty/wsl.toml"
fi

ln -s "$SOURCE_FILE" "$TARGET_DIR/alacritty.toml"
