{ lib, ... }:

{
  # workaround: xwayland-native-resolution
  # 在主机覆盖之后追加补丁，保留主机专用修复及补丁顺序。
  nixpkgs.overlays = lib.mkAfter [
    (final: prev: {
      mutter = prev.mutter.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          ./xwayland-native-resolution.patch
          ./xwayland-content-scale.patch
        ];
      });

      gnome-settings-daemon = prev.gnome-settings-daemon.overrideAttrs (oldAttrs: {
        # workaround: xwayland-content-dpi
        patches = (oldAttrs.patches or [ ]) ++ [ ./xwayland-content-dpi.patch ];
      });
    })
  ];

  programs.dconf.profiles.user.databases = [
    {
      # 仅在 logical 布局、单个逻辑显示器、自动 XWayland 缩放时生效。
      # gsettings 设为 false 可临时关闭；卸载补丁需移除 import 并重建、重新登录。
      settings."org/gnome/mutter/wayland".xwayland-native-resolution = true;
    }
  ];
}
