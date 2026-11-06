{ ... }:

{
  # 用户态 OOM 策略统一交给 earlyoom，内核 OOM killer 继续兜底。
  systemd.oomd.enable = false;

  services.earlyoom = {
    enable = true;
    # 可用内存和剩余 swap 同时低于 10% 时发 SIGTERM，低于 5% 时发 SIGKILL。
    freeMemThreshold = 10;
    freeSwapThreshold = 10;
    extraArgs = [
      "--prefer"
      "^strata-host$"
    ];
    # 不使用 -g：应用可能与 GNOME Shell 共享进程组，整组终止会结束桌面会话。
  };
}
