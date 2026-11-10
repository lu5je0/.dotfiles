#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TARGET="$HOME/.local/bin/q-trash"
VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$DOTFILES_DIR/module/q-trash/Cargo.toml" | head -n 1)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid q-trash version" >&2; exit 1; }

if [[ -x "$TARGET" ]] && [[ "$("$TARGET" --version 2>/dev/null || true)" == "q-trash $VERSION" ]]; then
  echo "skip: q-trash $VERSION already installed"
  exit 0
fi

case "$(uname -s)" in
  Linux) platform=linux ;;
  Darwin) platform=macos ;;
  *) echo "unsupported q-trash platform: $(uname -s)" >&2; exit 1 ;;
esac
# Android/Termux needs a Bionic build; Linux musl releases are not Android packages.
if [[ -n "${TERMUX_VERSION:-}" || "$(uname -o 2>/dev/null || true)" == Android ]]; then
  echo "q-trash releases do not support Android/Termux" >&2
  exit 1
fi
case "$(uname -m)" in
  x86_64|amd64) arch=x86_64 ;;
  aarch64|arm64) arch=aarch64 ;;
  *) echo "unsupported q-trash architecture: $(uname -m)" >&2; exit 1 ;;
esac
if [[ -d "$TARGET" ]]; then
  echo "cannot replace directory: $TARGET" >&2
  exit 1
fi
asset="q-trash-$platform-$arch"
base="https://github.com/lu5je0/.dotfiles/releases/download/q-trash-v$VERSION"
mkdir -p "$(dirname "$TARGET")"
work="$(mktemp -d "$(dirname "$TARGET")/.q-trash.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
curl --fail --location --retry 3 "$base/$asset" -o "$work/$asset"
curl --fail --location --retry 3 "$base/SHA256SUMS" -o "$work/SHA256SUMS"
checksum="$(awk -v name="$asset" '$2 == name {print $1}' "$work/SHA256SUMS")"
[[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || { echo "missing/invalid checksum for $asset" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$work/$asset" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$work/$asset" | awk '{print $1}')"
fi
[[ "$actual" == "$checksum" ]] || { echo "q-trash checksum mismatch" >&2; exit 1; }
chmod +x "$work/$asset"
[[ "$("$work/$asset" --version)" == "q-trash $VERSION" ]] || { echo "q-trash version mismatch" >&2; exit 1; }
# Replace the directory entry, including an obsolete setup symlink, not its target.
mv -f "$work/$asset" "$TARGET"
echo "installed: q-trash $VERSION → $TARGET"
