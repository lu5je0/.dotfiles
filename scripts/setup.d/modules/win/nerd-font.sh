#!/bin/bash
set -e

FONT_FILE="JetBrainsMonoNLNerdFontMono-Medium.ttf"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/NoLigatures/Medium/$FONT_FILE"
FONT_DIR="$WIN_HOME/AppData/Local/Microsoft/Windows/Fonts"
FONT_PATH="$FONT_DIR/$FONT_FILE"

if [[ -e "$FONT_PATH" ]]; then
  echo "skip: $FONT_PATH exists"
  exit 0
fi

mkdir -p "$FONT_DIR"
curl -fL -o "$FONT_PATH" "$FONT_URL"

/mnt/c/Windows/System32/reg.exe add \
  "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts" \
  /v "JetBrainsMonoNL Nerd Font Mono Medium (TrueType)" \
  /t REG_SZ /d "$(wslpath -w "$FONT_PATH")" /f

echo "font: installed to $FONT_PATH (re-login or restart apps to apply)"
