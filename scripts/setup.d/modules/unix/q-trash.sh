#!/bin/bash

REPO="lu5je0/.dotfiles"
BIN_DIR="$HOME/.local/bin/solid"
TARGET_BIN="$BIN_DIR/q-trash"

if [[ -x "$TARGET_BIN" ]]; then
  echo "skip: $TARGET_BIN already exists"
  exit 0
fi

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
echo "downloading q-trash from $url"
if curl -fsSL "$url" -o "$TARGET_BIN"; then
  chmod +x "$TARGET_BIN"
  echo "installed: $TARGET_BIN"
else
  echo "download failed; build manually: cd ~/.dotfiles/submodule/q-trash-rs && cargo build --release"
  exit 1
fi
