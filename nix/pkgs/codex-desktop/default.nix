{ pkgs, flake }:

# 官方 Linux 桌面包由上游适配 NixOS，启动命令为 chatgpt。
# 安装：nix profile add path:~/.dotfiles#codex-desktop
# 更新：nix flake update llm-agents，再 nix profile upgrade codex-desktop
flake.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt
