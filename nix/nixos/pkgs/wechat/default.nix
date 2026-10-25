{
  lib,
  symlinkJoin,
  writeShellApplication,
  systemd,
  jq,
  wechat,
}:

let
  launcher = writeShellApplication {
    name = "wechat";
    runtimeInputs = [
      systemd
      jq
    ];
    text = builtins.readFile ./launch.sh + ''
      exec ${lib.getExe wechat} "$@"
    '';
  };
in
symlinkJoin {
  name = "wechat-${wechat.version}-tray-activation";
  paths = [ wechat ];

  postBuild = ''
    rm "$out/bin/wechat"
    ln -s ${lib.getExe launcher} "$out/bin/wechat"

    # 托盘恢复不会完成新的启动通知；否则 GNOME 会停在 STARTING，忽略后续点击。
    rm "$out/share/applications/wechat.desktop"
    substitute ${wechat}/share/applications/wechat.desktop "$out/share/applications/wechat.desktop" \
      --replace-fail "Exec=wechat %U" "Exec=$out/bin/wechat %U" \
      --replace-fail "StartupNotify=true" "StartupNotify=false"
  '';

  passthru.unwrapped = wechat;
  inherit (wechat) meta;
}
