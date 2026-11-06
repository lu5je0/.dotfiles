{ ... }:

{
  systemd.oomd = {
    enable = true;
    # 使用 NixOS 内建的压力监控，覆盖系统服务、SSH 登录会话和用户服务。
    # 模块默认压力阈值为 80%，持续时间沿用 systemd 默认的 30 秒。
    enableSystemSlice = true;
    enableUserSlices = true;
  };

  # 全局 swap 兜底：内存和 swap 使用率都超过默认的 90% 时选择 cgroup 终止。
  systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";
}
