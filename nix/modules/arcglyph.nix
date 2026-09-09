{ pkgs, ... }:

let
  arcglyph = pkgs.callPackage ../pkgs/arcglyph.nix { };
in
{
  hardware.uinput.enable = true;

  users.users.lu5je0 = {
    extraGroups = [ "input" "uinput" ];
    packages = [ arcglyph ];
  };
}
