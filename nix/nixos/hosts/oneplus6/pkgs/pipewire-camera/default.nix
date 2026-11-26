{
  lib,
  pipewire,
  libcamera,
  symlinkJoin,
}:
let
  plugin = (pipewire.override { inherit libcamera; }).overrideAttrs (old: {
    pname = "oneplus6-pipewire-camera-plugin";
    # The stock PipeWire patch expects the libcamera 0.8 location enum names.
    patches =
      if lib.versionOlder libcamera.version "0.8" then
        builtins.filter (patch: baseNameOf (toString patch) != "libcamera-0.8-compat.patch") old.patches
      else
        old.patches;
    outputs = [ "out" ];
    buildPhase = ''
      runHook preBuild
      ninja -j$NIX_BUILD_CORES spa/plugins/libcamera/libspa-libcamera.so
      runHook postBuild
    '';
    installPhase = ''
      install -Dm755 spa/plugins/libcamera/libspa-libcamera.so \
        $out/lib/spa-0.2/libcamera/libspa-libcamera.so
    '';
    preInstall = "";
    postInstall = "";
    preFixup = "";
    postFixup = "";
    dontWrapGApps = true;
    doCheck = false;
  });
in
# SPA_PLUGIN_DIR selects this tree; retain all other stock SPA plugins.
symlinkJoin {
  name = "oneplus6-pipewire-camera-plugins-${pipewire.version}";
  paths = [
    plugin
    pipewire
  ];
}
