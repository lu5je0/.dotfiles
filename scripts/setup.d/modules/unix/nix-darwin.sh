#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
  echo "nix-darwin 仅支持 macOS" >&2
  exit 1
fi

if ! nix_bin=$(command -v nix); then
  echo "请先安装 Nix，再运行 nix-darwin" >&2
  exit 1
fi

: "${DOTFILES_DIR:?setup.py must set DOTFILES_DIR}"
# 使用 Git 取源，避免 path: 把 .git 中的 socket 等运行时文件也复制进 store。
flake="$DOTFILES_DIR"

sudo -H \
  "$nix_bin" --extra-experimental-features "nix-command flakes" \
  run "$flake#darwin-rebuild" -- switch --flake "$flake#mac"

# 成功切换后移除旧安装模块留下的用户级链接，系统配置已由 nix-darwin 管理。
legacy_config="$HOME/.config/nix/nix.conf"
if [[ -L "$legacy_config" ]] && \
  [[ $(readlink "$legacy_config") == "$DOTFILES_DIR/nix-mac/nix.conf" ]]; then
  rm "$legacy_config"
fi
