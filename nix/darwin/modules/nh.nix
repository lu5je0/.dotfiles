{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.nh ];
  environment.variables.NH_FLAKE = "/Users/lu5je0/.dotfiles";
}
