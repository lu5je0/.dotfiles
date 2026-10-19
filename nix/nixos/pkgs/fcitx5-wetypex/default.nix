{ pkgs, flake }:

# 复用上游包定义，并与 dotfiles 的系统 Fcitx5、Qt 使用同一套依赖。
pkgs.callPackage "${flake}/nix/package.nix" { }
