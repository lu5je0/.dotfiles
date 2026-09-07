{ pkgs, pkgsUnstable, ... }:

{
  imports = [
    ../modules/fcitx5-rime.nix
    ../modules/mission-center.nix
  ];

  environment.systemPackages = with pkgs; [
    gnomeExtensions.appindicator
    gnomeExtensions.astra-monitor
    gnomeExtensions.brightness-control-using-ddcutil
    gnomeExtensions.clipboard-indicator
    gnomeExtensions.dash-to-dock
    gnomeExtensions.gtk4-desktop-icons-ng-ding
    gnomeExtensions.show-desktop-button
    gnomeExtensions.transparent-top-bar-adjustable-transparency
    pkgsUnstable.gnomeExtensions.chinese-calendar
    google-chrome
    lutris
    pkgsUnstable.qq
    steam-run
    wechat
    wineWow64Packages.stable
    wpsoffice-cn
  ];

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb = {
    layout = "cn";
    variant = "";
  };

  fonts = {
    packages = with pkgs; [
      corefonts
      nerd-fonts.jetbrains-mono
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      stix-two
      symbola
      vista-fonts
    ];
    fontconfig = {
      defaultFonts = {
        sansSerif = [ "Noto Sans CJK SC" ];
        serif = [ "Noto Serif CJK SC" ];
        monospace = [ "JetBrainsMonoNL Nerd Font Mono" ];
      };
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <alias>
            <family>Symbol</family>
            <prefer><family>Symbola</family></prefer>
          </alias>
          <alias>
            <family>Wingdings</family>
            <prefer><family>Symbola</family></prefer>
          </alias>
          <alias>
            <family>Wingdings 2</family>
            <prefer><family>Symbola</family></prefer>
          </alias>
          <alias>
            <family>Wingdings 3</family>
            <prefer><family>Symbola</family></prefer>
          </alias>
          <alias>
            <family>MT Extra</family>
            <prefer><family>STIX Two Math</family></prefer>
          </alias>
        </fontconfig>
      '';
    };
  };

  hardware.graphics.enable32Bit = true;
  hardware.i2c.enable = true;

  services.flatpak.enable = true;
  services.printing.enable = false;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.firefox.enable = false;
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
          enabled-extensions = [
            pkgs.gnomeExtensions.appindicator.extensionUuid
            pkgs.gnomeExtensions.astra-monitor.extensionUuid
            pkgs.gnomeExtensions.brightness-control-using-ddcutil.extensionUuid
            pkgs.gnomeExtensions.clipboard-indicator.extensionUuid
            pkgs.gnomeExtensions.dash-to-dock.extensionUuid
            pkgs.gnomeExtensions.gtk4-desktop-icons-ng-ding.extensionUuid
            pkgs.gnomeExtensions.kimpanel.extensionUuid
            pkgs.gnomeExtensions.show-desktop-button.extensionUuid
            pkgs.gnomeExtensions.transparent-top-bar-adjustable-transparency.extensionUuid
            pkgsUnstable.gnomeExtensions.chinese-calendar.extensionUuid
          ];
        };
      };
    }
  ];

  nixpkgs.config.allowUnfree = true;
}
