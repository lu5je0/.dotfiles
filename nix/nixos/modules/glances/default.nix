{ lib, ... }:

{
  services.glances = {
    enable = true;
    openFirewall = lib.mkDefault true;
  };
}
