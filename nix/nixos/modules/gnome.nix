{
  lib,
  pkgs,
  pkgsUnstable,
  ...
}:

let
  tilewindow = pkgs.callPackage ../pkgs/tilewindow { };
  windowDecorations = pkgs.callPackage ../pkgs/window-decorations { };
  shellExtensions = [
    pkgs.gnomeExtensions.appindicator
    pkgs.gnomeExtensions.astra-monitor
    pkgs.gnomeExtensions.clipboard-indicator
    pkgs.gnomeExtensions.dash-to-dock
    pkgs.gnomeExtensions.gtk4-desktop-icons-ng-ding
    pkgs.gnomeExtensions.kimpanel
    pkgs.gnomeExtensions.show-desktop-button
    pkgs.gnomeExtensions.transparent-top-bar-adjustable-transparency
    pkgsUnstable.gnomeExtensions.chinese-calendar
    tilewindow
    windowDecorations
  ];
in
{
  imports = [
    ../pkgs/gtk-frdp/module.nix
    ../pkgs/window-decorations/module.nix
  ];

  environment.systemPackages = shellExtensions ++ [
    pkgs.gjs
    pkgs.gnome-tweaks
    # Qt6 应用（peazip 等）的 Adwaita 风格窗口装饰插件，配合下面的 QT_WAYLAND_DECORATION 使用
    pkgs.qadwaitadecorations-qt6
  ];

  # 修复qt应用窗口阴影
  # https://github.com/FedoraQt/QAdwaitaDecorations/pull/89
  # qt.enable 把 QT_PLUGIN_PATH 指到各 profile 的 lib/qt-6/plugins，Qt 插件装进 profile 才被找到
  qt.enable = true;
  environment.sessionVariables.QT_WAYLAND_DECORATION = "qadwaitadecorations";

  services.displayManager.gdm = {
    enable = true;
    # 登录界面保持待机可用，禁止空闲自动睡眠；不影响用户会话的电源设置。
    autoSuspend = false;
  };
  services.desktopManager.gnome.enable = true;
  services.gnome.gnome-remote-desktop.enable = true;
  systemd.user.services.gnome-remote-desktop = {
    enable = true;
    wantedBy = [ "gnome-session.target" ];
  };
  # GNOME 50 的设置仅在 system unit 状态为 enabled/disabled 时显示「远程桌面」入口，
  # NixOS 默认给的是 linked，补 wantedBy 让它变成 enabled
  systemd.services.gnome-remote-desktop.wantedBy = [ "graphical.target" ];
  # 「远程登录」开关由 configuration daemon 提权配置，而它的 PATH 里没有
  # /run/wrappers/bin（pkexec 所在），会报 Failed to execute child process "pkexec"
  systemd.services.gnome-remote-desktop-configuration.environment = {
    PATH = lib.mkForce "/run/wrappers/bin";
    SHELL = "/run/current-system/sw/bin/bash";
  };

  # networking.firewall.allowedTCPPorts = [ 3389 ];

  # Nautilus 右键「在终端中打开」，终端用系统安装的定制 kitty
  # （等价于 gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty）
  programs.nautilus-open-any-terminal = {
    enable = true;
    terminal = "kitty";
  };

  programs.dconf.profiles.user.databases = [
    {
      # 统一标题栏按钮，避免旧用户设置覆盖布局后隐藏按钮。
      locks = [ "/org/gnome/desktop/wm/preferences/button-layout" ];
      settings = {
        "org/gnome/desktop/interface" = {
          font-name = "Noto Sans CJK SC 11";
          document-font-name = "Noto Sans CJK SC 12";
          monospace-font-name = "JetBrainsMonoNL Nerd Font Mono 11";
          # GNOME 50 起默认关闭中键粘贴（primary selection），这里显式恢复
          gtk-enable-primary-paste = true;
        };
        "org/gnome/desktop/wm/preferences".button-layout = "appmenu:minimize,maximize,close";
        "org/gnome/shell" = {
          always-show-log-out = true;
          enabled-extensions = map (extension: extension.extensionUuid) shellExtensions;
        };
      };
    }
  ];
}
