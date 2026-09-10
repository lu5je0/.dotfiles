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
    cleanupInterval = "1h";
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

  # ── 内核卡死自动重启 ──
  # 参考：系统卡死时不需要强制关机，配置好后 30s 自动复位。
  # btrfs COW 保证文件系统不会坏，最多丢最近 30 秒未保存数据。
  boot.kernel.sysctl = {
    # 启用全部 Magic SysRq 功能。
    # 即使键盘上没有 SysRq 键，也能通过 SSH 执行：
    #   echo b > /proc/sysrq-trigger   # 重启
    "kernel.sysrq" = 1;
    # 内核检测到 CPU 长时间无法调度（软锁）→ 主动内核崩溃（panic）
    "kernel.softlockup_panic" = 1;
    # panic 后等 10 秒自动重启，留时间给 panic notifier 刷存储缓存
    "kernel.panic" = 10;
  };
  # 硬件 watchdog（Intel TCO），驱动 iTCO_wdt 已在内核中加载。
  # watchdogd 每 10 秒"喂狗"一次；如果内核完全卡死无人喂狗，
  # 30 秒后硬件定时器超时，直接触发主板复位（比长按电源键温和）。
  services.watchdogd = {
    enable = true;
  };

  # CPU 固定高性能
  powerManagement.cpuFreqGovernor = "performance";
  # GNOME 用 mkDefault 打开 power-profiles-daemon，它在 multi-user.target 之后启动，
  # 会把 governor 改回 powersave、EPP 改回 balance_performance，覆盖掉上面的设置。
  # 代价：GNOME 设置里的「电源模式」开关消失
  services.power-profiles-daemon.enable = false;

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
