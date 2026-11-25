{ pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.vicinae
    pkgs.gnomeExtensions.vicinae
  ];

  systemd.packages = [ pkgs.vicinae ];
  programs.dconf.profiles.user.databases = [
    { settings."org/gnome/shell/extensions/vicinae".show-status-indicator = false; }
  ];
  systemd.user.services.vicinae = {
    wantedBy = [ "graphical-session.target" ];
    enableDefaultPath = false;
  };
}
