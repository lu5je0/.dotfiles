#!/bin/bash
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

# wm/layout.json -> kwinrc [Script-tilewindow]，kwin 脚本通过 readConfig 读取
JSON=$(python3 -c '
import json, pathlib
src = pathlib.Path.home() / ".dotfiles" / "wm" / "layout.json"
print(json.dumps(json.loads(src.read_text()), separators=(",", ":"), ensure_ascii=False))
')
kwriteconfig6 --file kwinrc --group Script-tilewindow --key wm_layout_json "$JSON"

if [ -d "$HOME/.local/share/kwin/scripts/tilewindow" ]; then
    kpackagetool6 --type KWin/Script --upgrade "$DOTFILES_DIR/kwin/tilewindow"
else
    kpackagetool6 --type KWin/Script --install "$DOTFILES_DIR/kwin/tilewindow"
fi

qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript tilewindow 2>/dev/null || true
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$HOME/.local/share/kwin/scripts/tilewindow/contents/code/main.js" tilewindow
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start

kwriteconfig6 --file kwinrc --group Plugins --key tilewindowEnabled true

echo "done: layout synced and tilewindow reloaded"
