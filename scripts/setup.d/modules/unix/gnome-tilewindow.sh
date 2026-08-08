#!/bin/bash

SOURCE="$DOTFILES_DIR/gnome/tilewindow@lu5je0"
TARGET="$HOME/.local/share/gnome-shell/extensions/tilewindow@lu5je0"

glib-compile-schemas "$SOURCE/schemas/"

if [ ! -e "$TARGET" ]; then
    mkdir -p "$(dirname "$TARGET")"
    ln -s "$SOURCE" "$TARGET"
fi

gnome-extensions enable tilewindow@lu5je0 2>/dev/null \
    || echo "note: run 'gnome-extensions enable tilewindow@lu5je0' inside a GNOME session"
