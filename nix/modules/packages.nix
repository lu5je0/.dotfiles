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
    nmap
    vim
    fd
    tmux
    file
    cmake
    ncdu
    dnsutils
    bubblewrap
    socat
    ripgrep
    net-tools
  ];

  users.users.lu5je0.packages = with pkgs; [
    bun
    nodejs
    openssl
    stylua
    nixfmt
    nixfmt-tree
    opencc
    luajit
    yazi
    fzf
    fastfetch
    wget
    btop
    gh
    cargo
    gcc
    gnumake
    pkgsUnstable.neovim
    pkgsUnstable.pi-coding-agent
    rustc
    jq
    tree-sitter
  ];
}
