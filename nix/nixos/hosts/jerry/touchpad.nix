{ lib, pkgs, ... }:

{
  programs.wsf.enable = true;

  # 公共 GNOME 模块会把包的 extensionUuid 加入默认启用列表。
  environment.systemPackages = [ (pkgs.callPackage ./pkgs/touchpad-speed-control { }) ];

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/shell/extensions/touchpad-speed-control" = {
        global-factor = 0.5;
        h-global-factor = 0.5;
        # 上游内置的应用倍率为 1.0，会覆盖全局倍率；清空后统一使用半速。
        app-factors = lib.gvariant.mkEmptyArray "{sd}";
        h-app-factors = lib.gvariant.mkEmptyArray "{sd}";
      };
    }
  ];
}
