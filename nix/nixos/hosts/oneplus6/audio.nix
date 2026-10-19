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

  # QDSP6 accepts S24_LE but playback is silent; match the working S16_LE path.
  services.pipewire.wireplumber.extraConfig."51-oneplus6-audio" = {
    "monitor.alsa.rules" = [
      {
        matches = [ { "device.name" = "alsa_card.platform-sound"; } ];
        # Linear gain 0.8^3 corresponds to 80% in the desktop volume control.
        actions.update-props."device.routes.default-sink-volume" = 0.512;
      }
      {
        matches = [
          { "node.name" = "~alsa_output.platform-sound.*"; }
          { "node.name" = "~alsa_input.platform-sound.*"; }
        ];
        actions.update-props = {
          "audio.format" = "S16LE";
          "audio.rate" = 48000;
        };
      }
    ];
  };
}
