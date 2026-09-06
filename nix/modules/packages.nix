{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    kitty.terminfo
  ];

  users.users.lu5je0.packages = with pkgs; [
    cargo
    gcc
    neovim
    python3
    rustc
    tree-sitter
  ];
}
