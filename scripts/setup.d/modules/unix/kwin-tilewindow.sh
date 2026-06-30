#!/bin/bash

TARGET="$HOME/.local/share/kwin/scripts/tilewindow"
SOURCE="$DOTFILES_DIR/kwin/tilewindow"

if [ -d "$TARGET" ]; then
    kpackagetool6 --type KWin/Script --upgrade "$SOURCE"
else
    kpackagetool6 --type KWin/Script --install "$SOURCE"
fi

kwriteconfig6 --file kwinrc --group Plugins --key tilewindowEnabled true
