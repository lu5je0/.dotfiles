{ pkgs, ... }:

{
  # Xbox 蓝牙手柄使用带震动指令节流的 xpadneo，保留默认震动强度。
  hardware.xpadneo.enable = true;

  programs.steam = {
    enable = true;
    # workaround: steam-fhs-cursor-theme
    # Steam FHS needs the cursor theme to avoid a tiny fallback cursor: https://github.com/ValveSoftware/steam-for-linux/issues/12092
    extraPackages = [ pkgs.adwaita-icon-theme ];
    gamescopeSession = {
      enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    lutris
  ];
}
