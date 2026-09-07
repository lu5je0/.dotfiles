{ pkgs }:

{
  kitty = pkgs.callPackage ./kitty.nix { };
  qoder = pkgs.callPackage ./qoder.nix { };
}
