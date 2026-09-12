{ pkgs, inputs }:

{
  arcglyph = pkgs.callPackage ./arcglyph.nix { };
  emby-ext-player = pkgs.callPackage ./emby-ext-player.nix { };
  kitty = pkgs.callPackage ./kitty.nix { };
  mark-shot = pkgs.callPackage ./mark-shot { flake = inputs.mark-shot; };
  qoder = pkgs.callPackage ./qoder { };
  tilewindow = pkgs.callPackage ./tilewindow.nix { };
}
