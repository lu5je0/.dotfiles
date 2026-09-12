{ pkgs, pkgsUnstable, inputs, ... }:

{
  # mark-shot flake 只在 packages.<system>.default 暴露，注入后即可按 pkgs.mark-shot 使用
  nixpkgs.overlays = [
    (final: prev: {
      mark-shot = inputs.mark-shot.packages.${final.stdenv.hostPlatform.system}.default;
    })
  ];

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
    mark-shot
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
