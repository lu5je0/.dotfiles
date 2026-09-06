{ pkgs, pkgsUnstable, ... }:

{
  environment.systemPackages = with pkgs; [
    kitty.terminfo
  ];

  users.users.lu5je0.packages = with pkgs; [
    git
    nodejs
    ripgrep
    fzf
    htop
    fastfetch
    btop
    gh
    cargo
    gcc
    gnumake
    pkgsUnstable.neovim
    python3
    rustc
    tree-sitter
  ];
}
