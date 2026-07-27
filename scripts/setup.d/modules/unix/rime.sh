#!/bin/bash

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
if [[ "$(uname)" == "Darwin" ]]; then
  RIME_DIR="$HOME/Library/Rime"
else
  RIME_DIR="$HOME/.local/share/fcitx5/rime"
fi
CHECK="$RIME_DIR/cn_dicts"

if [[ -L "$CHECK" ]]; then
  echo "skip: $CHECK already linked"
  exit 0
fi

bash "$DOTFILES_DIR/rime/rime-install.sh"
