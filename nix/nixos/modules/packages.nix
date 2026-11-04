{ pkgs, pkgsUnstable, ... }:

let
  common = import ../../common/packages.nix { inherit pkgs pkgsUnstable; };
in
{
  nixpkgs.overlays = [
    (_final: prev: {
      btop = prev.callPackage ../pkgs/btop { inherit (prev) btop; };
    })
  ];

  environment.systemPackages =
    common.systemPackages
    ++ (with pkgs; [
      bubblewrap
      clang
      net-tools
    ]);

  users.users.lu5je0.packages =
    common.userPackages
    ++ (with pkgs; [
    ]);
}
