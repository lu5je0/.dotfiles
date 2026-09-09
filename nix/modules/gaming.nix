{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    # Steam FHS needs the cursor theme to avoid a tiny fallback cursor: https://github.com/ValveSoftware/steam-for-linux/issues/12092
    extraPackages = [ pkgs.adwaita-icon-theme ];
  };

  environment.systemPackages = with pkgs; [
    lutris
  ];
}
