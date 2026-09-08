{ pkgs }:

{
  arcglyph = pkgs.callPackage ./arcglyph.nix { };
  kitty = pkgs.callPackage ./kitty.nix { };
  qoder = pkgs.callPackage ./qoder.nix { };
  tilewindow = pkgs.callPackage ./tilewindow.nix { };
}
