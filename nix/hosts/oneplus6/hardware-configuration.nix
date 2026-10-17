{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-linux";
  # Follow the latest kernel provided by the pinned stable branch, as on huskar.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader = {
    grub.enable = false;
    systemd-boot.enable = false;
    generic-extlinux-compatible = {
      enable = true;
      configurationLimit = 3;
    };
    timeout = 3;
  };
  hardware.deviceTree = {
    enable = true;
    name = "qcom/sdm845-oneplus-enchilada.dtb";
  };

  boot.kernelParams = [ "console=tty0" ];
  boot.blacklistedKernelModules = [
    "ipa"
    "qcom_q6v5_mss"
  ];
  boot.initrd = {
    systemd.enable = true;
    systemd.tpm2.enable = false;
    includeDefaultModules = false;
    availableKernelModules = [
      "sd_mod"
      "ufs_qcom"
      "ufshcd_core"
      "ufshcd_pltfrm"
      "phy_qcom_qmp_ufs"
      "i2c_qcom_geni"
      "rmi_core"
      "rmi_i2c"
      "msm"
      "panel_samsung_sofef00"
      "ext4"
      "vfat"
    ];
    extraFirmwarePaths = [
      "qcom/a630_sqe.fw"
      "qcom/a630_gmu.bin"
      "qcom/sdm845/OnePlus/enchilada/a630_zap.mbn"
    ];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SYSTEM";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-label/NIXOS_BOOT";
      fsType = "vfat";
      options = [ "umask=0077" ];
    };
  };
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ (pkgs.callPackage ./pkgs/firmware { }) ];
  hardware.graphics.enable = true;
  hardware.bluetooth.enable = true;
  hardware.sensor.iio.enable = true;
}
