{ pkgs, pkgsUnstable, ... }:

let
  common = import ../../common/packages.nix { inherit pkgs pkgsUnstable; };
in
{
  environment.systemPackages =
    common.systemPackages
    ++ (with pkgs; [
      bubblewrap
      net-tools
    ]);

  users.users.lu5je0.packages =
    common.userPackages
    ++ (with pkgs; [
    ]);
}
