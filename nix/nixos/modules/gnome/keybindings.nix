{ lib, pkgs, ... }:

let
  customKeybindingsPath = "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings";
  customKeybindings = {
    mark-shot-capture = {
      name = "Mark Shot: 截图";
      # Mark Shot 由用户 profile 安装，命令通过 PATH 跟随 profile 升级。
      command = "mark-shot --capture";
      binding = "<Shift><Super>a";
    };
    vicinae = {
      name = "Vicinae";
      command = "${pkgs.vicinae}/bin/vicinae toggle";
      binding = "<Alt>space";
    };
  };
in
{
  programs.dconf.profiles.user.databases = [
    {
      # 快捷键由 Nix 统一管理，防止用户 dconf 中的旧值覆盖声明。
      lockAll = true;
      settings = {
        "org/gnome/desktop/wm/keybindings".activate-window-menu = lib.gvariant.mkEmptyArray "s";
        "org/gnome/settings-daemon/plugins/media-keys".custom-keybindings = map (
          name: "/${customKeybindingsPath}/${name}/"
        ) (builtins.attrNames customKeybindings);
      }
      // lib.mapAttrs' (
        name: value: lib.nameValuePair "${customKeybindingsPath}/${name}" value
      ) customKeybindings;
    }
  ];
}
