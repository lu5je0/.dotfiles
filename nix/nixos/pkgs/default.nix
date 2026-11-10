{
  pkgs,
  pkgsUnstable,
  inputs,
}:

{
  q-trash = pkgs.callPackage ./q-trash { };
  arcglyph = inputs.arcglyph.packages.${pkgs.stdenv.hostPlatform.system}.default;
  btop = pkgs.callPackage ./btop { };
  codex-desktop = pkgs.callPackage ./codex-desktop { flake = inputs.llm-agents; };
  window-decorations = pkgs.callPackage ./window-decorations { };
  emby-ext-player = pkgs.callPackage ./emby-ext-player { };
  fcitx5-rime = pkgs.callPackage ./fcitx5-rime { };
  fcitx5-wetypex = pkgs.callPackage ./fcitx5-wetypex { flake = inputs.fcitx5-wetypex; };
  kitty = pkgs.callPackage ./kitty { };
  mark-shot = pkgs.callPackage ./mark-shot { flake = inputs.mark-shot; };
  mission-center = pkgsUnstable.callPackage ./mission-center { };
  qoder = pkgs.callPackage ./qoder { };
  show-desktop-corner = pkgs.callPackage ./show-desktop-corner { };
  terminal-browser = pkgs.callPackage ./terminal-browser { };
  tilewindow = pkgs.callPackage ./tilewindow { };
  wechat = pkgs.callPackage ./wechat { };
  wps = pkgs.wpsoffice-cn;
}
