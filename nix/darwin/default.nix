{ ... }:

{
  imports = [
    ../common/nix.nix
    ./packages.nix
    ./modules/nh.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  # 本机切源选择由独立 TUI 保存，不随仓库同步；缺省使用原有缓存。
  nix.extraOptions = ''
    !include /etc/nix/source.conf
  '';

  # 首次使用本配置的 nix-darwin 状态版本；后续升级时保持不变。
  system.stateVersion = 7;
}
