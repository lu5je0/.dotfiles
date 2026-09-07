{ pkgs, pkgsUnstable, ... }:

{
  environment.systemPackages = with pkgs; [
    kitty.terminfo
    htop
    python3
    git
    uv
    p7zip
    zip
  ];

  users.users.lu5je0.packages = with pkgs; [
    nodejs
    ripgrep
    fzf
    fastfetch
    wget
    btop
    gh
    cargo
    gcc
    gnumake
    pkgsUnstable.neovim
    rustc
    jq
    tree-sitter
  ];
}
