#!/bin/bash
# mark-shot 托盘单色图标：symbolic SVG 链进 XDG 图标目录，
# 再让 GNOME AppIndicator 扩展按 SNI Id 覆盖图标名（顶栏只有按名拿到 -symbolic 才会自动染色）。

ICON_SRC="$DOTFILES_DIR/gnome/icons/mark-shot-symbolic.svg"
ICON_DST="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/symbolic/apps/mark-shot-symbolic.svg"
EXT=appindicatorsupport@rgcjonas.gmail.com
EXT_DIR="/run/current-system/sw/share/gnome-shell/extensions/$EXT"
SCHEMA=org.gnome.shell.extensions.appindicator
ENTRY="('mark-shot', 'mark-shot-symbolic', 'mark-shot-symbolic')"

mkdir -p "$(dirname "$ICON_DST")"
ln -sfn "$ICON_SRC" "$ICON_DST"
echo "✓ 图标链接 → $ICON_DST"

if [ ! -d "$EXT_DIR/schemas" ]; then
    echo "skip: 未装 AppIndicator 扩展，未写 gsettings"
    exit 0
fi

current=$(gsettings --schemadir "$EXT_DIR/schemas" get $SCHEMA custom-icons)
if [[ "$current" == *"$ENTRY"* ]]; then
    echo "skip: custom-icons 已包含 mark-shot"
else
    inner=$(printf '%s' "$current" | sed -e 's/^@a(sss) //' -e 's/^\[//' -e 's/\]$//')
    if [ -z "$(printf '%s' "$inner" | tr -d '[:space:]')" ]; then
        merged="[$ENTRY]"
    else
        merged="[$inner, $ENTRY]"
    fi
    gsettings --schemadir "$EXT_DIR/schemas" set $SCHEMA custom-icons "$merged"
    echo "✓ custom-icons += mark-shot → mark-shot-symbolic"
fi

# 设置变化不重建 indicator actor：若图标没更新或与旧位图叠画，手动重启扩展或重登：
#   gnome-extensions disable/enable appindicatorsupport@rgcjonas.gmail.com
