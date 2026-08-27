#!/bin/bash
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

# wm/layout.jsonc（JSONC，支持注释）-> kwinrc [Script-tilewindow]，
# kwin 脚本通过 readConfig 读取。python 侧先剥离注释再解析
JSON=$(python3 -c '
import json, pathlib

def strip_comments(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "\"":
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                elif text[j] == "\"":
                    j += 1
                    break
                else:
                    j += 1
            out.append(text[i:j])
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i + 2)
            i = n if j < 0 else j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)

src = pathlib.Path.home() / ".dotfiles" / "wm" / "layout.jsonc"
print(json.dumps(json.loads(strip_comments(src.read_text())), separators=(",", ":"), ensure_ascii=False))
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
