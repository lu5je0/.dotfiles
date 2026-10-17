{ pkgs, ... }:
let
  ucm = pkgs.callPackage ./pkgs/alsa-ucm { };
  ucmPath = "${ucm}/share/alsa/ucm2";
in
{
  environment.systemPackages = [ pkgs.alsa-utils ];
  environment.variables.ALSA_CONFIG_UCM2 = ucmPath;
  systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucmPath;
  systemd.user.services.pipewire-pulse.environment.ALSA_CONFIG_UCM2 = ucmPath;
  systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucmPath;
}
