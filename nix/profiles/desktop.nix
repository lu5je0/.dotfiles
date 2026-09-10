{ pkgs, pkgsUnstable, ... }:

{
  imports = [
    ../modules/arcglyph.nix
    ../modules/fcitx5-rime.nix
    ../modules/gnome.nix
    ../modules/keyd.nix
    ../modules/mission-center.nix
  ];

  environment.systemPackages = with pkgs; [
    google-chrome
    pkgsUnstable.qq
    steam-run
    telegram-desktop
    wechat
    mpv
    wineWow64Packages.stable
    wpsoffice-cn
  ];
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
}
