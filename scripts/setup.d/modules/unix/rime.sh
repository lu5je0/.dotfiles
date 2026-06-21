#!/bin/bash

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
RIME_DIR="$HOME/.local/share/fcitx5/rime"
CHECK="$RIME_DIR/cn_dicts"

if [[ -L "$CHECK" ]]; then
  echo "skip: $CHECK already linked"
  exit 0
fi

bash "$DOTFILES_DIR/rime/rime-install.sh"
