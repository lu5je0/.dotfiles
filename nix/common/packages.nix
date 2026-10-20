{ pkgs, pkgsUnstable }:

{
  # 保留 NixOS 原有的系统包 / 用户包归属；Darwin 将两组安装到系统环境。
  systemPackages = with pkgs; [
    kitty.terminfo
    htop
    (pkgsUnstable.python3.withPackages (pythonPackages: [ pythonPackages.requests ]))
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
    socat
    ripgrep
  ];

  userPackages = with pkgs; [
    bun
    nodejs
    openssl
    stylua
    zoxide
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
    gnumake
    pkgsUnstable.neovim
    pkgsUnstable.pi-coding-agent
    rustc
    jq
    tree-sitter
  ];
}
