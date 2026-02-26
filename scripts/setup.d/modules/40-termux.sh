#!/bin/bash
# DESC: termux config (~/.config/termux)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.config/termux"

if [[ -e "$TARGET" ]]; then
  echo "skip: $TARGET exists"
else
  mkdir -p "$HOME/.config"
  ln -s "$DOTFILES_DIR/termux" "$TARGET"
fi

TERMUX_FONT_URL="https://github.com/ryanoasis/nerd-fonts/raw/refs/heads/master/patched-fonts/JetBrainsMono/NoLigatures/Regular/JetBrainsMonoNLNerdFontMono-Regular.ttf"
TERMUX_FONT_PATH="$HOME/.termux/font.ttf"

mkdir -p "$TERMUX_HOME"
if [[ -e "$TERMUX_FONT_PATH" ]]; then
  echo "skip: $TERMUX_FONT_PATH exists"
else
  curl -L -o "$TERMUX_FONT_PATH" "$TERMUX_FONT_URL"
fi
