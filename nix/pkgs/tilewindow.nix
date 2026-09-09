{ lib, stdenvNoCC, glib }:

let
  uuid = "tilewindow@lu5je0";
in
stdenvNoCC.mkDerivation {
  pname = "gnome-shell-extension-tilewindow";
  version = "0-unstable";

  src = lib.cleanSource (../../gnome + "/${uuid}");

  nativeBuildInputs = [ glib ];

  buildPhase = ''
    runHook preBuild
    rm -f schemas/gschemas.compiled
    glib-compile-schemas --strict schemas
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/gnome-shell/extensions"
    cp -r -T . "$out/share/gnome-shell/extensions/${uuid}"
    runHook postInstall
  '';

  passthru.extensionUuid = uuid;

  meta = {
    description = "Window tiling shortcuts (port of the KWin tilewindow script)";
    platforms = lib.platforms.linux;
  };
}
