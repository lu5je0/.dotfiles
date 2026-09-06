{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      dbus
      libx11
      wayland
    ];
  };
}
