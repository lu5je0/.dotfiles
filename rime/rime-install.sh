#!/bin/bash
set -e

DOTFILES_RIME="$(cd "$(dirname "$0")" && pwd)"
RIME_ICE="$DOTFILES_RIME/rime-ice"

# Detect platform and set RIME data directory
if [[ "$(uname)" == "Darwin" ]]; then
  RIME_DIR="${HOME}/Library/Rime"
else
  RIME_DIR="${HOME}/.local/share/fcitx5/rime"
fi

mkdir -p "$RIME_DIR"

# Link upstream rime-ice files
for f in "$RIME_ICE"/*.yaml "$RIME_ICE"/*.txt; do
  [ -f "$f" ] && ln -sf "$f" "$RIME_DIR/"
done

# Link upstream directories
for d in cn_dicts en_dicts lua opencc; do
  [ -d "$RIME_ICE/$d" ] && ln -sfn "$RIME_ICE/$d" "$RIME_DIR/$d"
done

# Link personal customizations (override upstream)
for f in "$DOTFILES_RIME"/*.custom.yaml "$DOTFILES_RIME"/custom_phrase.txt; do
  [ -f "$f" ] && ln -sf "$f" "$RIME_DIR/"
done

echo "rime: linked to $RIME_DIR"

# Link fcitx5 config (Linux only)
if [[ "$(uname)" != "Darwin" ]]; then
  DOTFILES_FCITX5="$(dirname "$DOTFILES_RIME")/fcitx5"
  FCITX5_CONFIG_DIR="${HOME}/.config/fcitx5"
  mkdir -p "$FCITX5_CONFIG_DIR/conf"

  ln -sf "$DOTFILES_FCITX5/config" "$FCITX5_CONFIG_DIR/config"
  for f in "$DOTFILES_FCITX5/conf"/*; do
    [ -f "$f" ] && ln -sf "$f" "$FCITX5_CONFIG_DIR/conf/"
  done

  echo "fcitx5: config linked to $FCITX5_CONFIG_DIR"
  echo "run 'fcitx5 -r' or redeploy from tray to apply"
else
  echo "run 'Squirrel/Redeploy' from menu bar to apply"
fi
