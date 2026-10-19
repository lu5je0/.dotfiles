{ pkgs, pkgsUnstable, ... }:

let
  common = import ../common/packages.nix { inherit pkgs pkgsUnstable; };
  userPackages =
    common.userPackages
    ++ (with pkgs; [
      # 在这里添加 Mac 专属的个人软件。
    ]);
in
{
  environment.systemPackages =
    common.systemPackages
    ++ userPackages
    ++ [
      pkgs.clang
    ];
}
