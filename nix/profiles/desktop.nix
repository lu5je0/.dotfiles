{ pkgs, pkgsUnstable, ... }:

{
  imports = [
    ../modules/fcitx5-rime.nix
    ../modules/mission-center.nix
  ];

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb = {
    layout = "cn";
    variant = "";
  };

  fonts = {
    packages = with pkgs; [
      noto-fonts-cjk-sans
      nerd-fonts.jetbrains-mono
    ];
    fontconfig.defaultFonts = {
      sansSerif = [ "Noto Sans CJK SC" ];
      monospace = [ "JetBrainsMonoNL Nerd Font Mono" ];
    };
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
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/interface" = {
          font-name = "Noto Sans CJK SC 11";
          document-font-name = "Noto Sans CJK SC 12";
          monospace-font-name = "JetBrainsMonoNL Nerd Font Mono 11";
        };
        "org/gnome/shell" = {
          always-show-log-out = true;
          enabled-extensions = with pkgs.gnomeExtensions; [
            appindicator.extensionUuid
            dash-to-dock.extensionUuid
            kimpanel.extensionUuid
          ];
        };
      };
    }
  ];

  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock
    google-chrome
    lutris
    pkgsUnstable.qq
    steam-run
    wechat
    wpsoffice
  ];
}
