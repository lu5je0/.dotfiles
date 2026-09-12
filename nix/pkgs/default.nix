{ pkgs }:

{
  arcglyph = pkgs.callPackage ./arcglyph.nix { };
  emby-ext-player = pkgs.callPackage ./emby-ext-player.nix { };
  kitty = pkgs.callPackage ./kitty.nix { };
  qoder = pkgs.callPackage ./qoder { };
  tilewindow = pkgs.callPackage ./tilewindow.nix { };
}
