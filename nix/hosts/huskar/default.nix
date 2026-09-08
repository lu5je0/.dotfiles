{ lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = false;
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    configurationLimit = 20;
    useOSProber = false;
  };
  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/efi";
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;

  fileSystems = {
    "/".options = [ "compress=zstd:3" "ssd" "discard=async" "noatime" ];
    "/home".options = [ "compress=zstd:3" "ssd" "discard=async" "noatime" ];
    "/nix".options = [ "compress=zstd:3" "ssd" "discard=async" "noatime" ];
    "/.snapshots".options = [ "compress=zstd:3" "ssd" "discard=async" "noatime" ];
    "/home/.snapshots".options = [ "compress=zstd:3" "ssd" "discard=async" "noatime" ];
  };

  networking.hostName = "huskar";
  networking.networkmanager.enable = true;

  users.groups.lu5je0.gid = 1000;
  users.users.root.hashedPasswordFile = "/etc/nixos/root-password-hash";
  users.users.lu5je0 = {
    uid = 1000;
    group = "lu5je0";
    hashedPasswordFile = "/etc/nixos/lu5je0-password-hash";
  };

  system.stateVersion = "26.05";
}
