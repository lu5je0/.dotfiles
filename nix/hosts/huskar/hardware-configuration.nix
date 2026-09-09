{ config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/f4037ed9-577a-4e48-a838-1a0ed6fd2eda";
    fsType = "btrfs";
    options = [ "subvol=@" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/f4037ed9-577a-4e48-a838-1a0ed6fd2eda";
    fsType = "btrfs";
    options = [ "subvol=@home" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/f4037ed9-577a-4e48-a838-1a0ed6fd2eda";
    fsType = "btrfs";
    options = [ "subvol=@nix" ];
  };

  fileSystems."/.snapshots" = {
    device = "/dev/disk/by-uuid/f4037ed9-577a-4e48-a838-1a0ed6fd2eda";
    fsType = "btrfs";
    options = [ "subvol=@snapshots" ];
  };

  fileSystems."/home/.snapshots" = {
    device = "/dev/disk/by-uuid/f4037ed9-577a-4e48-a838-1a0ed6fd2eda";
    fsType = "btrfs";
    options = [ "subvol=@home-snapshots" ];
  };

  fileSystems."/efi" = {
    device = "/dev/disk/by-uuid/AD45-689A";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  fileSystems."/mnt/d" = {
    device = "/dev/disk/by-uuid/FC64FF6A64FF2654";
    fsType = "ntfs";
    options = [
      "nofail"
      "uid=1000"
      "gid=1000"
      "iocharset=utf8"
      "x-systemd.device-timeout=5s"
    ];
  };

  fileSystems."/mnt/e" = {
    device = "/dev/disk/by-uuid/74F281FEF281C4B8";
    fsType = "ntfs";
    options = [
      "nofail"
      "uid=1000"
      "gid=1000"
      "iocharset=utf8"
      "x-systemd.device-timeout=5s"
    ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
