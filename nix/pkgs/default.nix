{ pkgs, inputs }:

{
  arcglyph = pkgs.callPackage ./arcglyph.nix { };
  codex-desktop = pkgs.callPackage ./codex-desktop { flake = inputs.llm-agents; };
  window-decorations = pkgs.callPackage ./window-decorations { };
  emby-ext-player = pkgs.callPackage ./emby-ext-player.nix { };
  fcitx5-wetypex = pkgs.callPackage ./fcitx5-wetypex { flake = inputs.fcitx5-wetypex; };
  kitty = pkgs.callPackage ./kitty.nix { };
  mark-shot = pkgs.callPackage ./mark-shot { flake = inputs.mark-shot; };
  qoder = pkgs.callPackage ./qoder { };
  terminal-browser = pkgs.callPackage ./terminal-browser { };
  tilewindow = pkgs.callPackage ./tilewindow.nix { };
}
