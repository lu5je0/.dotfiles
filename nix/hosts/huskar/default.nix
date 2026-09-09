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
    "/mnt/d" = {
      device = "/dev/disk/by-uuid/FC64FF6A64FF2654";
      fsType = "ntfs3";
      options = [
        "nofail"
          "uid=1000"
          "gid=1000"
          "iocharset=utf8"
          "x-systemd.device-timeout=5s"
      ];
    };
    "/mnt/e" = {
      device = "/dev/disk/by-uuid/74F281FEF281C4B8";
      fsType = "ntfs3";
      options = [
        "nofail"
          "uid=1000"
          "gid=1000"
          "iocharset=utf8"
          "x-systemd.device-timeout=5s"
      ];
    };
  };

  services.snapper = {
    snapshotInterval = "hourly";
    cleanupInterval = "1d";
    persistentTimer = true;
    configs.home = {
      SUBVOLUME = "/home";
      FSTYPE = "btrfs";
      ALLOW_USERS = [ "lu5je0" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 10;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 2;
      TIMELINE_LIMIT_YEARLY = 0;
    };
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
