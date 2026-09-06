{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nix-ld.nix
    ../../modules/packages.nix
    ../../modules/zsh.nix
  ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    useOSProber = true;
    fsIdentifier = "provided";
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.sessionVariables.NPM_CONFIG_PREFIX = "/home/lu5je0/.local";
  environment.localBinInPath = true;

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "zh_CN.UTF-8";
    LC_IDENTIFICATION = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_MONETARY = "zh_CN.UTF-8";
    LC_NAME = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_TELEPHONE = "zh_CN.UTF-8";
    LC_TIME = "zh_CN.UTF-8";
  };

  users.users.lu5je0 = {
    isNormalUser = true;
    description = "lu5je0";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  services.openssh.enable = true;

  system.stateVersion = "26.05";
}
