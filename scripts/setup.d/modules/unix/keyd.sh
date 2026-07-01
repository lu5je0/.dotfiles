#!/bin/bash

SOURCE="$DOTFILES_DIR/keyd/default.conf"
TARGET="/etc/keyd/default.conf"

if [ "$(readlink -f "$TARGET" 2>/dev/null)" = "$SOURCE" ]; then
    echo "skip: $TARGET already linked"
    exit 0
fi

sudo mkdir -p /etc/keyd
sudo ln -sfn "$SOURCE" "$TARGET"
sudo systemctl enable --now keyd
sudo keyd.rvaiya reload 2>/dev/null || sudo systemctl restart keyd
