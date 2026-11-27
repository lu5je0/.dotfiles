{ pkgs, pkgsUnstable, ... }:

let
  kitty = pkgs.callPackage ../nixos/pkgs/kitty { };
  common = import ../common/packages.nix {
    inherit pkgs pkgsUnstable;
    kittyTerminfo = kitty.terminfo;
  };
  userPackages =
    common.userPackages
    ++ (with pkgs; [
      google-chrome
      kitty
      # 在这里添加 Mac 专属的个人软件。
    ]);
in
{
  environment.systemPackages =
    common.systemPackages
    ++ userPackages
    ++ [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];

  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
}
