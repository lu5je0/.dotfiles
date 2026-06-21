#!/bin/bash

RIME_DIR="$WIN_HOME/AppData/Roaming/Rime"
RIME_ICE="$DOTFILES_DIR/rime/rime-ice"
RIME_CUSTOM="$DOTFILES_DIR/rime"

mkdir -p "$RIME_DIR"

CMD=/mnt/c/Windows/System32/cmd.exe

# Link upstream directories (junction for dirs)
for d in cn_dicts en_dicts lua opencc; do
  TARGET="$RIME_DIR/$d"
  if [ -e "$TARGET" ]; then
    continue
  fi
  $CMD /c sudo mklink /J \
    "$(wslpath -w "$TARGET")" \
    "$(wslpath -w "$RIME_ICE/$d")"
done

# Link upstream yaml/txt files
for f in "$RIME_ICE"/*.yaml "$RIME_ICE"/*.txt; do
  [ -f "$f" ] || continue
  TARGET="$RIME_DIR/$(basename "$f")"
  if [ -e "$TARGET" ]; then
    continue
  fi
  $CMD /c sudo mklink \
    "$(wslpath -w "$TARGET")" \
    "$(wslpath -w "$f")"
done

# Link personal customizations (override upstream)
for f in "$RIME_CUSTOM"/*.custom.yaml "$RIME_CUSTOM"/custom_phrase.txt; do
  [ -f "$f" ] || continue
  TARGET="$RIME_DIR/$(basename "$f")"
  # Remove upstream link if exists, personal takes priority
  if [ -L "$TARGET" ] || [ -e "$TARGET" ]; then
    rm -f "$TARGET"
  fi
  $CMD /c sudo mklink \
    "$(wslpath -w "$TARGET")" \
    "$(wslpath -w "$f")"
done

echo "rime: linked to $RIME_DIR"
echo "Please click 'Redeploy' in Weasel tray icon to apply."
