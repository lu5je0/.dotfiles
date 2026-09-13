{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ESP 挂在 /boot（hardware-configuration.nix 里生成），GRUB 装进 ESP，device = "nodev"
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    configurationLimit = 20;
    useOSProber = false;
  };
  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot";
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;

  fileSystems = {
    "/".options = [ "compress=zstd:3" "ssd" "discard=async" "noatime" ];
    "/home".options = [ "compress=zstd:3" "ssd" "discard=async" "noatime" ];
    "/nix".options = [ "compress=zstd:3" "ssd" "discard=async" "noatime" ];
  };

  hardware.bluetooth.enable = true;

  # 笔记本保留 power-profiles-daemon（GNOME 电源模式），不套用 huskar 的 performance 固定调优
  services.power-profiles-daemon.enable = true;

  networking.hostName = "jerry";
  networking.networkmanager.enable = true;

  system.stateVersion = "26.05";
}
