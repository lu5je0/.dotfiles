{
  lib,
  runCommand,
  fcitx5-rime,
  rime-ice,
}:

let
  rimeConfig = ../../../../ime/rime;
  rimeData = runCommand "rime-ice-personal-${rime-ice.version}" { } ''
    mkdir -p "$out/share/rime-data"
    cp -rL ${rime-ice}/share/rime-data/. "$out/share/rime-data/"
    chmod -R u+w "$out/share/rime-data"

    # Nixpkgs 将雾凇的 default.yaml 改名，恢复后才能使用其完整默认设置。
    cp "$out/share/rime-data/rime_ice_suggestion.yaml" "$out/share/rime-data/default.yaml"
    cp ${rimeConfig}/default.custom.yaml ${rimeConfig}/rime_ice.custom.yaml \
      ${rimeConfig}/custom_phrase.txt ${rimeConfig}/rime.lua "$out/share/rime-data/"
  '';
in
(fcitx5-rime.override { rimeDataPkgs = [ rimeData ]; }).overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    # 用户 profile 的 lib/fcitx5 不在系统 Fcitx wrapper 的插件搜索路径里。
    substituteInPlace "$out/share/fcitx5/addon/rime.conf" \
      --replace-fail 'Library=export:librime' "Library=export:$out/lib/fcitx5/librime"
    mkdir -p "$out/share/fcitx5/themes"
    cp -r ${../../../../ime/themes/wechat} ${../../../../ime/themes/wechat-dark} \
      "$out/share/fcitx5/themes/"
  '';

  meta = old.meta // {
    description = "Fcitx5 Rime with Rime Ice and personal configuration";
    license = with lib.licenses; [
      lgpl21Plus
      gpl3Only
    ];
  };
})
