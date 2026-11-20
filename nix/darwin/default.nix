{ ... }:

{
  imports = [
    ../common/nix.nix
    ./packages.nix
    ./modules/nh.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  environment.variables = {
    NPM_CONFIG_PREFIX = "$HOME/.local";
  };

  # 首次使用本配置的 nix-darwin 状态版本；后续升级时保持不变。
  system.stateVersion = 7;
}
