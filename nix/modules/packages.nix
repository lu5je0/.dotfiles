{ pkgs, pkgsUnstable, ... }:

{
  environment.systemPackages = with pkgs; [
    kitty.terminfo
    htop
    (pkgsUnstable.python3.withPackages (pythonPackages: [
      pythonPackages.requests
    ]))
    git
    uv
    p7zip
    zip
    unzip
    vim
    tmux
    file
    ncdu
  ];

  users.users.lu5je0.packages = with pkgs; [
    bun
    pkgsUnstable.pi-coding-agent
    nodejs
    stylua
    opencc
    ripgrep
    luajit
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
