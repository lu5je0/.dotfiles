{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.fn-ctrl;
in
{
  options.services.fn-ctrl = {
    enable = lib.mkEnableOption "jerry 的 EC Fn/Ctrl 输入桥接";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./pkgs/fn-ctrl { inherit (config.boot.kernelPackages) kernel; };
      description = "包含 C 输入桥接及匹配当前内核的只读 EC 模块。";
    };
    idleIntervalMs = lib.mkOption {
      type = lib.types.ints.between 5 1000;
      default = 100;
      description = "空闲 EC 检查间隔；Fn 配合鼠标的识别延迟上限约为此值加 EC 读取时间。";
    };
    heldIntervalMs = lib.mkOption {
      type = lib.types.ints.between 5 1000;
      default = 10;
      description = "Fn 按住时检查松开的间隔；键盘事件始终立即读取 EC。";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.keyd.enable;
        message = "jerry 的 Fn/Ctrl 桥接需要启用 keyd。";
      }
      {
        assertion = cfg.heldIntervalMs <= cfg.idleIntervalMs;
        message = "Fn 按住检查间隔不能大于空闲检查间隔。";
      }
    ];
    boot.extraModulePackages = [ cfg.package.kernelModule ];
    hardware.uinput.enable = true;

    # test/switch 不一定更新运行内核的 modprobe 搜索树，直接加载构建产物。
    # 加载权限只给一次性单元，常驻输入服务仍不持有 CAP_SYS_MODULE。
    systemd.services.fn-ctrl-module = {
      description = "Load the read-only Fn EC module";
      after = [ "systemd-modules-load.service" ];
      before = [ "fn-ctrl.service" ];
      restartTriggers = [ cfg.package.kernelModule ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        CapabilityBoundingSet = [ "CAP_SYS_MODULE" ];
        NoNewPrivileges = true;
      };
      script = ''
        if [ -e /sys/kernel/fn_ctrl_ec/modifiers ]; then
          exit 0
        fi
        runningKernel=$(${pkgs.coreutils}/bin/readlink -f /run/booted-system/kernel)
        if [ "$runningKernel" != "${config.boot.kernelPackages.kernel}/bzImage" ]; then
          echo "fn_ctrl_ec: running kernel differs from configured kernel; reboot first" >&2
          exit 1
        fi
        ${pkgs.kmod}/bin/insmod \
          ${cfg.package.kernelModule}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/extra/fn_ctrl_ec.ko
      '';
    };

    # 原始设备由桥接独占，keyd 处理替代设备 1209:f1c0，保留公共改键规则。
    services.keyd.keyboards.default.ids = lib.mkAfter [ "-0001:0001" ];
    systemd.services.keyd = {
      wants = [ "fn-ctrl.service" ];
      after = [ "fn-ctrl.service" ];
    };
    systemd.services.fn-ctrl = {
      description = "Fn to Ctrl bridge for the internal keyboard";
      wantedBy = [ "multi-user.target" ];
      requires = [ "fn-ctrl-module.service" ];
      after = [ "fn-ctrl-module.service" ];
      before = [ "keyd.service" ];
      unitConfig = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 6;
      };
      serviceConfig = {
        Type = "notify";
        ExecStart = "${lib.getExe cfg.package} ${toString cfg.idleIntervalMs} ${toString cfg.heldIntervalMs}";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 15;
        TimeoutStopSec = 5;
        WatchdogSec = 30;
        RuntimeDirectory = "fn-ctrl";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictSUIDSGID = true;
        DevicePolicy = "closed";
        DeviceAllow = [
          "char-input r"
          "/dev/uinput rw"
        ];
      };
    };
  };
}
