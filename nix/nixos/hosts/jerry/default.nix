{ pkgs, pkgsUnstable, ... }:

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
    "/".options = [
      "compress=zstd:3"
      "ssd"
      "discard=async"
      "noatime"
    ];
    "/home".options = [
      "compress=zstd:3"
      "ssd"
      "discard=async"
      "noatime"
    ];
    "/nix".options = [
      "compress=zstd:3"
      "ssd"
      "discard=async"
      "noatime"
    ];
  };

  hardware.bluetooth.enable = true;

  # 笔记本保留 power-profiles-daemon（GNOME 电源模式），不套用 huskar 的 performance 固定调优
  services.power-profiles-daemon.enable = true;

  # systemd 在 EFI HibernateLocation 中记录 swap 文件的设备和偏移，initrd 据此恢复。
  boot.initrd.systemd.enable = true;

  # 磁盘 swap 保存休眠镜像；日常换页仍优先使用公共配置中 priority = 5 的 zram。
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 16 * 1024;
      priority = 0;
    }
  ];

  # 独立子卷避免活动 swap 文件阻止根子卷创建快照；NixOS 用 btrfs mkswapfile 建文件。
  systemd.services.mkswap-swap-swapfile.preStart = ''
    if [ ! -e /swap ]; then
      ${pkgs.btrfs-progs}/bin/btrfs subvolume create /swap
    fi
    chmod 0700 /swap
  '';

  # GNOME 50 的电源菜单休眠入口。
  environment.systemPackages = [ pkgsUnstable.gnomeExtensions.hibernate-power-menu ];

  networking.hostName = "jerry";
  networking.networkmanager.enable = true;

  system.stateVersion = "26.05";
}
