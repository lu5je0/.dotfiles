{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      dbus
      libx11
      openssl
      stdenv.cc.cc.lib
      vulkan-loader
      wayland
    ];
  };
}
