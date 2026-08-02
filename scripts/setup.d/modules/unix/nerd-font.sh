#!/bin/bash
set -e

FONT_FILE="JetBrainsMonoNLNerdFontMono-Regular.ttf"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/NoLigatures/$FONT_FILE"

# WSL: font must be installed on the Windows side (terminals render there)
if [[ "$(uname -a)" == *WSL* ]]; then
  WIN_HOME="$(wslpath "$(/mnt/c/Windows/System32/cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")"
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
    /v "JetBrainsMonoNL Nerd Font Mono Regular (TrueType)" \
    /t REG_SZ /d "$(wslpath -w "$FONT_PATH")" /f

  echo "font: installed to $FONT_PATH (re-login or restart apps to apply)"
  exit 0
fi

# Termux: terminal font lives in ~/.termux/font.ttf
if [[ -n "$TERMUX_VERSION" ]]; then
  TERMUX_FONT_PATH="$HOME/.termux/font.ttf"
  if [[ -e "$TERMUX_FONT_PATH" ]]; then
    echo "skip: $TERMUX_FONT_PATH exists"
  else
    mkdir -p "$HOME/.termux"
    curl -fL -o "$TERMUX_FONT_PATH" "$FONT_URL"
    echo "font: installed to $TERMUX_FONT_PATH"
  fi
fi

if [[ "$(uname)" == "Darwin" ]]; then
  FONT_DIR="$HOME/Library/Fonts"
else
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
