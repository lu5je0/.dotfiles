#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../../.." && pwd)
PACKAGE_FILE="$SCRIPT_DIR/default.nix"
DOWNLOAD_URL="https://download.qoder.com/qoder-app/releases/latest/Qoder-linux-amd64.deb"
TEMP_DIR=$(mktemp -d)
PACKAGE_BACKUP="$TEMP_DIR/qoder.nix"
BUILD_SUCCEEDED=0
PACKAGE_CHANGED=0

cleanup() {
  local status=$?

  if [[ $status -ne 0 && $PACKAGE_CHANGED -eq 1 && $BUILD_SUCCEEDED -eq 0 ]]; then
    cp "$PACKAGE_BACKUP" "$PACKAGE_FILE"
    printf '构建失败，已恢复 %s\n' "$PACKAGE_FILE" >&2
  fi

  rm -rf "$TEMP_DIR"
  exit "$status"
}
trap cleanup EXIT

for command in nix jq perl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf '缺少命令: %s\n' "$command" >&2
    exit 1
  fi
done

printf '正在获取 Qoder 最新安装包...\n'
prefetch_json=$(nix store prefetch-file --refresh --json "$DOWNLOAD_URL")
source_hash=$(jq -er '.hash' <<<"$prefetch_json")
source_path=$(jq -er '.storePath' <<<"$prefetch_json")

mkdir "$TEMP_DIR/package"
nix shell nixpkgs#dpkg nixpkgs#asar --command bash -c '
  set -euo pipefail
  dpkg-deb --extract "$1" "$2/package"
  cd "$2"
  asar extract-file "$2/package/opt/Qoder/resources/app.asar" package.json
' bash "$source_path" "$TEMP_DIR"

version=$(jq -er '.version | select(type == "string" and length > 0)' "$TEMP_DIR/package.json")
if [[ ! $version =~ ^[0-9]+([.][0-9A-Za-z-]+)+$ ]]; then
  printf '安装包中的版本号无效: %s\n' "$version" >&2
  exit 1
fi
if [[ ! $source_hash =~ ^sha256-[A-Za-z0-9+/]+={0,2}$ ]]; then
  printf '安装包哈希格式无效: %s\n' "$source_hash" >&2
  exit 1
fi

current_version=$(perl -ne 'print "$1\n" if /^\s*version = "([^"]+)";/' "$PACKAGE_FILE")
current_hash=$(perl -ne 'print "$1\n" if /^\s*hash = "([^"]+)";/' "$PACKAGE_FILE")

if [[ $current_version != "$version" || $current_hash != "$source_hash" ]]; then
  cp "$PACKAGE_FILE" "$PACKAGE_BACKUP"
  QODER_VERSION="$version" QODER_HASH="$source_hash" perl -0pi -e '
    $version_count = s/(pname = "qoder";\n\s+version = ")[^"]+/$1$ENV{QODER_VERSION}/;
    $hash_count = s/(url = "https:\/\/download\.qoder\.com\/qoder-app\/releases\/latest\/Qoder-linux-amd64\.deb";\n\s+hash = ")[^"]+/$1$ENV{QODER_HASH}/;
    die "无法更新 Qoder 版本和哈希\n" unless $version_count == 1 && $hash_count == 1;
  ' "$PACKAGE_FILE"
  PACKAGE_CHANGED=1
  printf 'Qoder: %s -> %s\n' "$current_version" "$version"
else
  printf 'Qoder %s 的包定义已经是最新。\n' "$version"
fi

printf '正在构建 Qoder %s...\n' "$version"
nix build "path:$REPO_ROOT#qoder" --no-link
BUILD_SUCCEEDED=1

profile_json=$(nix profile list --json)
if jq -e '.elements.qoder' >/dev/null <<<"$profile_json"; then
  original_url=$(jq -er '.elements.qoder.originalUrl' <<<"$profile_json")
  nix profile upgrade qoder --override-flake "$original_url" "path:$REPO_ROOT"
else
  nix profile install "path:$REPO_ROOT#qoder"
fi

printf 'Qoder %s 更新完成。\n' "$version"
