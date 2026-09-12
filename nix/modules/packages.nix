{ pkgs, pkgsUnstable, ... }:

{
  environment.systemPackages = with pkgs; [
    kitty.terminfo
    gnome-tweaks
    htop
    (pkgsUnstable.python3.withPackages (pythonPackages: [
      pythonPackages.requests
    ]))
    git
    uv
    p7zip
    zip
    pstree
    unzip
    vim
    tmux
    file
    cmake
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
    yazi
    fzf
    fastfetch
    wl-clipboard
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
