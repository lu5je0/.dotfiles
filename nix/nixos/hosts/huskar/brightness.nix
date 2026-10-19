{ config, pkgs, ... }:

{
  # 灭屏期间重配显示器时，Mutter 50 会因 DRM enabled=disabled 丢掉背光，唤醒后不再恢复。
  # 修正背光与接口的匹配逻辑；只覆盖 huskar，让 GNOME Shell 使用同一份修补后的 Mutter。
  nixpkgs.overlays = [
    (final: prev: {
      mutter = prev.callPackage ./pkgs/mutter { inherit (prev) mutter; };
    })
  ];

  # 外接显示器默认没有 /sys/class/backlight 设备，GNOME 原生滑块无法控制硬件亮度。
  # ddcci-driver 通过 DDC/CI 将显示器暴露为标准背光设备，供 GNOME 原生亮度控制使用；
  # 驱动随当前内核编译，并在启动时加载 ddcci-backlight。
  # Linux 6.8+ 不支持自动探测，下面的服务在 GDM 启动前绑定 DP-1 的 AUX 总线；
  # GNOME 不会立即识别会话启动后新增的背光设备，所以绑定必须早于登录界面。
  # 重建并重启后，检查 /sys/class/backlight/ 是否出现 ddcci*，以及 GNOME 的原生亮度滑块。
  boot.extraModulePackages = [
    # 长时间灭屏后，显示器可能 ACK 了恢复请求却仍停在调暗值；驱动读回确认并有限重试。
    (pkgs.callPackage ./pkgs/ddcci-driver {
      inherit (config.boot.kernelPackages) ddcci-driver;
    })
  ];
  boot.kernelModules = [ "ddcci-backlight" ];

  systemd.services.ddcci-backlight-attach = {
    description = "Attach DDC/CI backlight on the DP-1 AUX bus";
    wantedBy = [ "graphical.target" ];
    before = [ "display-manager.service" ];
    after = [ "systemd-modules-load.service" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 90;
    };
    script = ''
      # AUX 总线出现时显示器可能尚未响应；探测失败后节点仍会留下，必须重试 bind。
      # 按总线名称匹配，避免写死可能变化的 i2c-9。
      for attempt in $(seq 1 30); do
        for adapter in /sys/bus/i2c/devices/i2c-*; do
          [ -r "$adapter/name" ] || continue
          [ "$(cat "$adapter/name")" = "AMDGPU DM aux hw bus 0" ] || continue
          bus="''${adapter##*/i2c-}"
          if [ -d "/sys/class/backlight/ddcci$bus" ]; then
            echo "DDC/CI backlight ddcci$bus ready (attempt $attempt)"
            exit 0
          fi
          if [ -e "/sys/bus/i2c/devices/$bus-0037" ]; then
            # 已注册但 probe 失败的节点没有 driver 链接，重新 bind 才会再次探测。
            if [ ! -L "/sys/bus/i2c/devices/$bus-0037/driver" ]; then
              printf '%s\n' "$bus-0037" > /sys/bus/i2c/drivers/ddcci/bind || true
            fi
          else
            printf 'ddcci 0x37\n' > "$adapter/new_device" || true
          fi
          if [ -d "/sys/class/backlight/ddcci$bus" ]; then
            echo "DDC/CI backlight ddcci$bus ready (attempt $attempt)"
            exit 0
          fi
          echo "DDC/CI probe on i2c-$bus not ready (attempt $attempt/30), retrying" >&2
          break
        done
        sleep 1
      done
      echo "DP-1 DDC/CI backlight did not become ready after 30 attempts" >&2
      exit 1
    '';
  };
}
