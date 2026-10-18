{ lib, pkgs, ... }:
{
  imports = [
    ../modules/gnome.nix
    ../modules/keyd.nix
  ];

  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans
    nerd-fonts.jetbrains-mono
  ];

  programs.dconf.profiles = {
    user.databases = [
      {
        settings."org/gnome/desktop/a11y/applications".screen-keyboard-enabled = true;
      }
    ];
    gdm.databases = [
      {
        settings."org/gnome/desktop/a11y/applications".screen-keyboard-enabled = true;
      }
    ];
  };

  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;
  services.flatpak.enable = true;
  # Keep Docker available on demand without delaying the phone's login screen.
  virtualisation.docker.enableOnBoot = false;
  # GDM and GNOME Shell use their native on-screen keyboard with IBus.
  i18n.inputMethod.ibus.engines = [ pkgs.ibus-engines.libpinyin ];

  nix.settings = {
    # One builder at a time; each package can still compile on four cores.
    max-jobs = lib.mkDefault 1;
    cores = lib.mkDefault 4;
  };
}
