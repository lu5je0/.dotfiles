{ pkgs, ... }:

let
  arcglyph = pkgs.callPackage ../pkgs/arcglyph.nix { };
in
{
  hardware.uinput.enable = true;

  users.users.lu5je0 = {
    extraGroups = [ "input" "uinput" ];
    packages = [ arcglyph ];
  };

  # arcglyph 写自启条目时优先用 /usr/bin/arcglyph，不存在才回退 current_exe()，
  # 而在 nix wrapper 下那是裸的 .arcglyph-wrapped（缺 LD_LIBRARY_PATH，登录即崩）。
  # 该软链经用户 profile 始终指向当前 generation 的 wrapper，跨 rebuild/GC 有效。
  systemd.tmpfiles.rules = [
    "L+ /usr/bin/arcglyph - - - - /etc/profiles/per-user/lu5je0/bin/arcglyph"
  ];
}
