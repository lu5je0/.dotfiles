{ config, pkgs, ... }:

let
  user = "lu5je0";
  home = config.users.users.${user}.home;
  configFile = "/etc/q-restic/config.json";

  # 关闭自动运行后仍可 sudo systemctl start restic-home 手动触发。
  enableTimer = true;

  # 备份逻辑在 module/q-restic/，入口符号链接是 bin/common/q-restic。
  # 定时任务直接调用 python3；q-restic 只使用标准库。
  #
  # 用户入口默认合并本模块部署的配置，手动执行与定时任务读取同一份 profile。
  # CLI 仓库操作必须显式指定配置文件和 profile。
  script = "${home}/.dotfiles/module/q-restic/q-restic.py";
in
{
  environment.etc."q-restic/config.json".text = builtins.toJSON {
    profiles.home = {
      sources = [ home ];
      repository = "sftp:${user}@192.168.1.10:/mnt/mg08/backups/restic/huskar";
      run_as = user;
      excludes = "/etc/q-restic/huskar-excludes.txt";
      host = "huskar";
      tag = "home";
      snapshot_tag = "home";
      mount_dir = "/tmp/restic-mnt";
      restore_dir = "${home}/restic-restore";
      keep = {
        hourly = 0;
        daily = 7;
        weekly = 4;
        monthly = 1;
        yearly = 0;
      };
    };
  };
  environment.etc."q-restic/huskar-excludes.txt".source = ./excludes.txt;

  # q-restic 要求 restic 已在 PATH 里（不再用 nix build 兜底）。
  #
  # 注意两处都得配，分工不同：
  #   environment.systemPackages → 只影响 /run/current-system/sw/bin，供手动执行用；
  #   systemd.services.<name>.path → 生成 unit 时把路径写进 PATH，systemd 跑才认这个。
  # unit 的 PATH 是求值时按 path 选项固定生成的（默认 coreutils/findutils/gnugrep/
  # gnused/systemd，见 nixos/lib/systemd-lib.nix 的 enableDefaultPath），跟 systemPackages
  # 完全无关；只写 systemPackages 的话定时任务会因 PATH 里找不到 restic 而失败。
  environment.systemPackages = [ pkgs.restic ];

  systemd.services.restic-home = {
    description = "restic 增量备份 home 到 NAS";

    # q-restic 的 NAS 预检和 restic 默认的 SFTP 传输都需要 ssh。
    # hostname 不需要——detect_host() 用的是 socket.gethostname()，跟 PATH 无关。
    path = [ pkgs.restic pkgs.openssh ];

    # 仓库走 SFTP，不依赖 /mnt/mg08 的 CIFS 挂载，所以只等网络就绪。
    # 顺带避开 CIFS 的 x-systemd.idle-timeout=600 自动卸载。
    # 这也意味着不需要 RequiresMountsFor=/mnt/mg08。
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # 脚本不在（比如没装 dotfiles）时静默跳过，而不是每天报失败。
    unitConfig.ConditionPathExists = script;

    serviceConfig = {
      Type = "oneshot";
      # 保持用户的 SSH 身份、HOME、缓存和写锁；只为本服务授予跨属主读取权限。
      User = user;
      Group = config.users.users.${user}.group;
      # 包括 root 的 0600 文件和 0700 目录；不授予绕过写权限或修改属主的能力。
      # Ambient 集让权限经过 Python/子进程 exec 传给 restic，普通 q-restic 不带此权限。
      AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
      CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
      ExecStart = "${pkgs.python3}/bin/python3 ${script} -c ${configFile} -p home backup";
      Nice = 10;
      IOSchedulingClass = "idle";

      # 要读遍整个 home，不能开 ProtectHome。
      ProtectHome = false;
      NoNewPrivileges = true;
    };
  };

  systemd.timers.restic-home = {
    # enableTimer = false 时只是不自动启动，单元本身仍然可用：
    #   sudo systemctl start restic-home          # 立即备份一次
    #   sudo systemctl start restic-home.timer    # 临时开始按计划跑（重启后失效）
    wantedBy = if enableTimer then [ "timers.target" ] else [ ];

    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      # 避免与 nix.gc / 其他夜间任务挤在一起；也让同一天的多次触发不重叠。
      RandomizedDelaySec = "30min";
      # 关机或休眠期间错过的触发，开机后补跑一次。
      Persistent = true;
    };
  };
}
