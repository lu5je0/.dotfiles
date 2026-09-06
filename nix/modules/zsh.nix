{ pkgs, ... }:

{
  programs.zsh.enable = true;
  users.users.lu5je0.shell = pkgs.zsh;
}
