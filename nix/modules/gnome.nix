{ pkgs, pkgsUnstable, ... }:

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

  networking.firewall.allowedTCPPorts = [ 3389 ];

  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/interface" = {
          font-name = "Noto Sans CJK SC 11";
          document-font-name = "Noto Sans CJK SC 12";
          monospace-font-name = "JetBrainsMonoNL Nerd Font Mono 11";
        };
        "org/gnome/shell" = {
          always-show-log-out = true;
          enabled-extensions = map (extension: extension.extensionUuid) shellExtensions;
        };
      };
    }
  ];
}
