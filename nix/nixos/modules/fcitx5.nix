{ pkgs, inputs, ... }:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = [
        pkgs.fcitx5-gtk
        (pkgs.callPackage ../pkgs/fcitx5-wetypex { flake = inputs.fcitx5-wetypex; })
      ];
      waylandFrontend = false;
      settings.inputMethod = {
        GroupOrder."0" = "Default";
        "Groups/0" = {
          "Default Layout" = "us";
          DefaultIM = "wetypex";
          Name = "Default";
        };
        "Groups/0/Items/0" = {
          Layout = "us";
          Name = "wetypex";
        };
        "Groups/0/Items/1".Name = "keyboard-us";
      };
    };
  };
}
