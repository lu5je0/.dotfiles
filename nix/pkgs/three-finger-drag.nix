{
  lib,
  stdenvNoCC,
}:

let
  uuid = "three-finger-drag@lu5je0";
in
stdenvNoCC.mkDerivation {
  pname = "gnome-shell-extension-three-finger-drag";
  version = "1";

  src = lib.cleanSource (../../gnome + "/${uuid}");

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/gnome-shell/extensions"
    cp -r -T . "$out/share/gnome-shell/extensions/${uuid}"
    runHook postInstall
  '';

  passthru.extensionUuid = uuid;

  meta = {
    description = "macOS-style three-finger drag (held primary button) for the GNOME touchpad";
    platforms = lib.platforms.linux;
  };
}
