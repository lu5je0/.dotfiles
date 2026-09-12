{ pkgs, pkgsUnstable, inputs, ... }:

{
  # mark-shot flake 只在 packages.<system>.default 暴露，注入后即可按 pkgs.mark-shot 使用；
  # 补丁让它默认向托盘宿主发 -symbolic 图标名（GNOME 顶栏只对该后缀按前景色染色），
  # 并把单色 SVG 装进包内供宿主按名解析，不再依赖 AppIndicator custom-icons 覆盖（见 gnome/AGENTS.md）
  nixpkgs.overlays = [
    (final: prev: {
      mark-shot = inputs.mark-shot.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../pkgs/mark-shot/mark-shot-tray-symbolic.patch ];
        postInstall = (old.postInstall or "") + ''
          install -Dm644 ${../../gnome/icons/mark-shot-symbolic.svg} \
            $out/share/icons/hicolor/symbolic/apps/mark-shot-symbolic.svg
        '';
      });
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
