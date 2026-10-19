{ config, pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-linux";
  # Keep the tested 7.2 series: camera, WLAN and charger modules need validation
  # before moving to another series. Patch releases still follow flake.lock.
  boot.kernelPackages = pkgs.linuxPackages_7_2;
  # Keep the cached stock kernel; rebuild only the two affected WLAN modules.
  boot.extraModulePackages = [
    (pkgs.callPackage ./pkgs/ath10k-wcn3990 {
      kernel = config.boot.kernelPackages.kernel;
    })
  ];
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
    dtbSource = pkgs.callPackage ./pkgs/device-tree {
      kernel = config.boot.kernelPackages.kernel;
    };
  };

  boot.kernelParams = [ "console=tty0" ];
  # CPUFreq obtains its throttling IRQs from LMh after the OSM interconnect
  # becomes available. Load that IRQ provider before triggering CPUFreq probe.
  boot.extraModprobeConfig = "softdep icc_osm_l3 pre: lmh";
  boot.blacklistedKernelModules = [
    "ipa"
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
    # These consumers otherwise wait until the full root udev coldplug;
    # CPU scaling and the display appeared only after about five minutes.
    kernelModules = [
      "lmh"
      "icc_osm_l3"
      "qcom_refgen_regulator"
      "phy_qcom_qusb2"
      "rtc_pm8xxx"
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
