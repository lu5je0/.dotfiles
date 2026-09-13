#!/bin/bash

REPO="git@github.com:lu5je0/mpv-lazy.git"
CLONE="$HOME/.local/share/mpv-lazy"
CONF="$CLONE/portable_config"
LINK="$HOME/.config/mpv"

linked=0
if [[ -L "$LINK" && "$(readlink "$LINK")" == "$CONF" ]]; then
  linked=1
elif [[ -e "$LINK" || -L "$LINK" ]]; then
  echo "error: $LINK exists and is not a symlink to $CONF"
  exit 1
fi

if [[ -d "$CLONE/.git" ]]; then
  echo "note: reuse existing clone at $CLONE (git pull to update)"
elif [[ -e "$CLONE" ]]; then
  echo "error: $CLONE exists but is not a git clone"
  exit 1
else
  mkdir -p "$(dirname "$CLONE")"
  # --no-cone: cone 模式会连带取出仓库根目录的 Windows 便携包（~110M）
  git clone --filter=blob:none --no-checkout "$REPO" "$CLONE" &&
    git -C "$CLONE" sparse-checkout set --no-cone '/portable_config/' &&
    git -C "$CLONE" checkout || exit 1
fi

if [[ $linked == 1 ]]; then
  echo "skip: $LINK already linked"
else
  mkdir -p "$(dirname "$LINK")"
  ln -s "$CONF" "$LINK"
  echo "linked: $LINK -> $CONF"
fi
