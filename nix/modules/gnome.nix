{ lib, pkgs, pkgsUnstable, ... }:

let
  tilewindow = pkgs.callPackage ../pkgs/tilewindow.nix { };
  shellExtensions = [
    pkgs.gnomeExtensions.appindicator
    pkgs.gnomeExtensions.astra-monitor
    pkgs.gnomeExtensions.brightness-control-using-ddcutil
    pkgs.gnomeExtensions.clipboard-indicator
    pkgs.gnomeExtensions.dash-to-dock
    pkgs.gnomeExtensions.gtk4-desktop-icons-ng-ding
    pkgs.gnomeExtensions.kimpanel
    pkgs.gnomeExtensions.show-desktop-button
    pkgs.gnomeExtensions.transparent-top-bar-adjustable-transparency
    pkgsUnstable.gnomeExtensions.chinese-calendar
    tilewindow
  ];
in
{
  environment.systemPackages = shellExtensions ++ [ pkgs.gjs ];

  services.displayManager.gdm.enable = true;
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

  networking.firewall.allowedTCPPorts = [ 3389 ];

  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/interface" = {
          font-name = "Noto Sans CJK SC 11";
          document-font-name = "Noto Sans CJK SC 12";
          monospace-font-name = "JetBrainsMonoNL Nerd Font Mono 11";
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
