{ pkgs, ... }:

{
  services.desktopManager.gnome.sessionPath = [ (pkgs.callPackage ./nautilus-my-computer { }) ];

  # Nautilus 右键「在终端中打开」使用系统安装的定制 kitty。
  programs.nautilus-open-any-terminal = {
    enable = true;
    terminal = "kitty";
  };

  programs.dconf.profiles.user.databases = [
    { settings."io/github/yannmasoch/nautilus-my-computer".start-on-disks = true; }
  ];
}
