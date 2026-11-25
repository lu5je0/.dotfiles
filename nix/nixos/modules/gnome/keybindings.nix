{ lib, pkgs, ... }:

let
  customKeybindingsPath = "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings";
  customKeybindings = {
    mark-shot-capture = {
      name = "Mark Shot: 截图";
      # 桌面门户通过 scope 识别 Mark Shot，才能复用记住的屏幕共享选择。
      command = "${pkgs.runtimeShell} -c 'exec ${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet --slice=app.slice --unit=app-gnome-io.github.jswysnemc.MarkShot-$$.scope mark-shot'";
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
        "org/gnome/desktop/wm/keybindings" = {
          activate-window-menu = lib.gvariant.mkEmptyArray "s";
          switch-to-workspace-left = [
            "<Super>Left"
            "<Super>Page_Up"
            "<Super>KP_Prior"
            "<Super><Alt>Left"
            "<Control><Alt>Left"
          ];
          switch-to-workspace-right = [
            "<Super>Right"
            "<Super>Page_Down"
            "<Super>KP_Next"
            "<Super><Alt>Right"
            "<Control><Alt>Right"
          ];
        };
        "org/gnome/mutter/keybindings" = {
          toggle-tiled-left = lib.gvariant.mkEmptyArray "s";
          toggle-tiled-right = lib.gvariant.mkEmptyArray "s";
        };
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
