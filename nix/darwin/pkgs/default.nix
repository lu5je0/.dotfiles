{ pkgs, inputs }:

let
  commonPkgs = ../../common/pkgs;
in
{
  inherit (inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}) darwin-rebuild;
  emby-ext-player = pkgs.callPackage (commonPkgs + "/emby-ext-player") { };
  kitty = pkgs.callPackage (commonPkgs + "/kitty") { };
}
