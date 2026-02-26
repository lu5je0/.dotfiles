#!/bin/bash
# DESC: copy maven config (~/.m2/settings.xml)?

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET_DIR="$HOME/.m2"

mkdir -p "$TARGET_DIR"
cp -i "$DOTFILES_DIR/m2/settings.xml" "$TARGET_DIR/settings.xml"
