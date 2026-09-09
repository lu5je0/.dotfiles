{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    extraPackages = [ pkgs.adwaita-icon-theme ];
    # package = pkgs.steam.override {
    #   extraEnv.XCURSOR_SIZE = "40";
    # };
  };

  environment.systemPackages = with pkgs; [
    lutris
  ];
}
