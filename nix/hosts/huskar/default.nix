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

  # 阻止 NixOS 因 fsType = "ntfs" 而安装 ntfs-3g，从而提供 /run/current-system/sw/bin/mount.ntfs。
  # util-linux 的 `mount -t ntfs` 会优先使用 mount.<type> helper 而非内核模块，结果挂成 fuseblk。
  # 压掉后才能让 /mnt/d、/mnt/e 真正走内核里的 ntfs（NTFSPLUS）模块。
  boot.supportedFilesystems.ntfs = lib.mkForce false;

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
    "/.snapshots".options = [
      "compress=zstd:3"
      "ssd"
      "discard=async"
      "noatime"
    ];
    "/home/.snapshots".options = [
      "compress=zstd:3"
      "ssd"
      "discard=async"
      "noatime"
    ];
    # NTFS 驱动切换：fsType = "ntfs" 走内核新驱动（kernel 7.1+ 的 NTFS，原 NTFSPLUS，作者 Namjae Jeon，
    # 模块 ntfs.ko、mount type = ntfs）；改回 "ntfs3" 则走 Paragon 老驱动（模块 ntfs3.ko）。
    # 新驱动不认 ntfs3 的布尔 prealloc 选项；共有的 uid/gid/iocharset 可照常保留。
    # nocase：大小写不敏感，和 Windows 行为对齐，避免造出仅大小写不同的同名文件
    # （NTFS 本身大小写敏感，Windows Win32 API 却按不敏感处理，会产生 Explorer 看不见的“幽灵文件”）。
    "/mnt/d" = {
      device = "/dev/disk/by-uuid/FC64FF6A64FF2654";
      fsType = "ntfs";
      options = [
        "nofail"
        "uid=1000"
        "gid=1000"
        "iocharset=utf8"
        "nocase"
        "x-systemd.device-timeout=5s"
      ];
    };
    "/mnt/e" = {
      device = "/dev/disk/by-uuid/74F281FEF281C4B8";
      fsType = "ntfs";
      options = [
        "nofail"
        "uid=1000"
        "gid=1000"
        "iocharset=utf8"
        "nocase"
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

  # snapper/btrfs 图形管理（浏览、对比、恢复快照，scrub/balance）。
  # 必须进 systemPackages：polkit 只扫描 /run/current-system/sw/share/polkit-1，
  # 放进用户 profile 会让 pkexec 找不到 action 而无法提权。
  environment.systemPackages = [ pkgs.btrfs-assistant ];

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

  # 关闭 WiFi 省电。NM 侧默认是 "ignore"（不管 mac80211 PS），显式关掉；
  # iwlmvm 固件档位默认 2=balanced，改 1=active（modinfo: 1-active/2-balanced/3-low power），重启后生效
  networking.networkmanager.wifi.powersave = false;
  boot.extraModprobeConfig = "options iwlmvm power_scheme=1\n";

  # 关闭防火墙
  networking.firewall.enable = false;

  system.stateVersion = "26.05";
}
