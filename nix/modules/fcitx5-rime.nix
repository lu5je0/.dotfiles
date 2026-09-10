{ pkgs, ... }:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        fcitx5-gtk
        fcitx5-rime
      ];
      waylandFrontend = false;
      settings.inputMethod = {
        GroupOrder."0" = "Default";
        "Groups/0" = {
          "Default Layout" = "us";
          DefaultIM = "rime";
          Name = "Default";
        };
        "Groups/0/Items/0" = {
          Layout = "us";
          Name = "rime";
        };
        "Groups/0/Items/1".Name = "keyboard-us";
      };
    };
  };
}
