{ config, pkgs, ... }:

let
  user = "lu5je0";
  home = config.users.users.${user}.home;

  # 定时器总开关。false = 单元已写好但不自动运行，可随时手动
  #   sudo systemctl start restic-home
  # 触发一次。等首次全量跑通、确认排除效果后再改成 true 并 rebuild。
  enableTimer = true;

  # 备份逻辑在 submodule/q-restic/，入口符号链接是 bin/common/q-restic。
  # 这里直接调 python3 而不走那个入口：入口经 runner.sh 用 uv 起 venv，
  # 对常驻定时任务来说是多余的一层（要 uv、要 .venv 可用、要能求值 flake），
  # 而 q-restic 只用标准库，python3 直接跑就够了。
  #
  # 仓库地址/主机过滤/保留策略都在 q-restic 自己的配置文件里，不在这里重复声明：
  #   ~/.config/q-restic/config.json
  # 没这份配置时（新机器）默认按本机短名推导，即
  #   sftp:lu5je0@192.168.1.10:/mnt/mg08/backups/restic/<hostname>
  # 并把 --host 也设成同一个短名，所以每台机器的快照互相看得到但只有自己的。
  # 以前这里有个写死 "huskar" 的 repo 变量，改成 ExecStart 调 q-restic 后就没人用了，
  # 留着只会误导（q-restic 会用自己配置里的值覆盖 RESTIC_REPOSITORY）。
  script = "${home}/.dotfiles/submodule/q-restic/q-restic.py";
in
{
  # q-restic 要求 restic 已在 PATH 里（不再用 nix build 兜底），
  # 所以这里必须装：systemd 服务的 PATH 只含系统 profile。
  environment.systemPackages = [ pkgs.restic ];

  systemd.services.restic-home = {
    description = "restic 增量备份 home 到 NAS";

    # 仓库走 SFTP，不依赖 /mnt/mg08 的 CIFS 挂载，所以只等网络就绪。
    # 顺带避开 CIFS 的 x-systemd.idle-timeout=600 自动卸载。
    # 这也意味着不需要 RequiresMountsFor=/mnt/mg08。
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # 脚本不在（比如没装 dotfiles）时静默跳过，而不是每天报失败。
    unitConfig.ConditionPathExists = script;

    serviceConfig = {
      Type = "oneshot";
      # 以用户身份跑，不用 root：home 里的文件本来就都属于这个用户。
      User = user;
      Group = config.users.users.${user}.group;
      ExecStart = "${pkgs.python3}/bin/python3 ${script} backup";
      Nice = 10;
      IOSchedulingClass = "idle";

      # 要读遍整个 home，不能开 ProtectHome。
      # 也不要开 PrivateTmp：备份按仓库取 flock 防并发，私有 /tmp 会让它
      # 和手动执行时拿到的锁不是同一个。
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
