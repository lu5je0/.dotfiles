{ pkgs, inputs }:

{
  arcglyph = pkgs.callPackage ./arcglyph.nix { };
  codex-desktop = pkgs.callPackage ./codex-desktop { flake = inputs.llm-agents; };
  # 旧属性保留，已安装的用户 profile 升级时仍可解析。
  codex-window-decorations = pkgs.callPackage ./window-decorations { };
  window-decorations = pkgs.callPackage ./window-decorations { };
  emby-ext-player = pkgs.callPackage ./emby-ext-player.nix { };
  kitty = pkgs.callPackage ./kitty.nix { };
  mark-shot = pkgs.callPackage ./mark-shot { flake = inputs.mark-shot; };
  qoder = pkgs.callPackage ./qoder { };
  terminal-browser = pkgs.callPackage ./terminal-browser { };
  tilewindow = pkgs.callPackage ./tilewindow.nix { };
}
