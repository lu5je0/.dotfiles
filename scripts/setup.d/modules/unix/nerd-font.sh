#!/bin/bash
set -e

BASE_URL="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/NoLigatures"

# WSL: font must be installed on the Windows side (terminals render there)
if [[ "$(uname -a)" == *WSL* ]]; then
  WIN_HOME="$(wslpath "$(/mnt/c/Windows/System32/cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")"
  FONT_FILE="JetBrainsMonoNLNerdFontMono-Medium.ttf"
  FONT_DIR="$WIN_HOME/AppData/Local/Microsoft/Windows/Fonts"
  FONT_PATH="$FONT_DIR/$FONT_FILE"

  if [[ -e "$FONT_PATH" ]]; then
    echo "skip: $FONT_PATH exists"
    exit 0
  fi

  mkdir -p "$FONT_DIR"
  curl -fL -o "$FONT_PATH" "$BASE_URL/Medium/$FONT_FILE"

  /mnt/c/Windows/System32/reg.exe add \
    "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts" \
    /v "JetBrainsMonoNL Nerd Font Mono Medium (TrueType)" \
    /t REG_SZ /d "$(wslpath -w "$FONT_PATH")" /f

  echo "font: installed to $FONT_PATH (re-login or restart apps to apply)"
  exit 0
fi

if [[ "$(uname)" == "Darwin" ]]; then
  FONT_FILE="JetBrainsMonoNLNerdFontMono-Regular.ttf"
  FONT_URL="$BASE_URL/Regular/$FONT_FILE"
  FONT_DIR="$HOME/Library/Fonts"
else
  FONT_FILE="JetBrainsMonoNLNerdFontMono-Medium.ttf"
  FONT_URL="$BASE_URL/Medium/$FONT_FILE"
  FONT_DIR="$HOME/.local/share/fonts"
fi

FONT_PATH="$FONT_DIR/$FONT_FILE"

if [[ -e "$FONT_PATH" ]]; then
  echo "skip: $FONT_PATH exists"
  exit 0
fi

mkdir -p "$FONT_DIR"
curl -fL -o "$FONT_PATH" "$FONT_URL"
echo "font: installed to $FONT_PATH"

if command -v fc-cache >/dev/null; then
  fc-cache -f "$FONT_DIR"
fi
