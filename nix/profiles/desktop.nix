{ pkgs, qoderDeb, ... }:

let
  qoder = pkgs.callPackage ../pkgs/qoder.nix { src = qoderDeb; };
in
{
  imports = [ ../modules/mission-center.nix ];

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb = {
    layout = "cn";
    variant = "";
  };

  hardware.graphics.enable32Bit = true;

  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.firefox.enable = true;
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    google-chrome
    lutris
    qoder
  ];
}
