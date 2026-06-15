#!/bin/bash

REPO="lu5je0/.dotfiles"
BIN_DIR="$HOME/.local/bin"
TARGET_BIN="$BIN_DIR/q-trash"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)  target="aarch64-apple-darwin" ;;
  Linux-x86_64)  target="x86_64-unknown-linux-gnu" ;;
  Linux-aarch64) target="aarch64-unknown-linux-gnu" ;;
  *)
    echo "unsupported platform: $(uname -s)-$(uname -m)"
    exit 1
    ;;
esac

mkdir -p "$BIN_DIR"

url="https://github.com/$REPO/releases/latest/download/q-trash-${target}"
tmp="${TARGET_BIN}.tmp"

if ! curl -fsSL "$url" -o "$tmp"; then
  rm -f "$tmp"
  echo "download failed; build manually: cd ~/.dotfiles/submodule/q-trash-rs && cargo build --release"
  exit 1
fi

chmod +x "$tmp"

if [[ -x "$TARGET_BIN" ]]; then
  old_ver=$("$TARGET_BIN" --version 2>/dev/null || echo "unknown")
  new_ver=$("$tmp" --version 2>/dev/null || echo "unknown")
  if [[ "$old_ver" == "$new_ver" ]]; then
    rm -f "$tmp"
    echo "already up to date: $old_ver"
  else
    mv -f "$tmp" "$TARGET_BIN"
    echo "updated: $old_ver -> $new_ver"
  fi
else
  mv -f "$tmp" "$TARGET_BIN"
  echo "installed: $($TARGET_BIN --version 2>/dev/null)"
fi
