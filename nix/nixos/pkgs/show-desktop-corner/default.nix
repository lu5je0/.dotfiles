{
  lib,
  stdenvNoCC,
  nodejs,
}:

let
  uuid = "show-desktop-corner@lu5je0";
in
stdenvNoCC.mkDerivation {
  pname = "gnome-shell-extension-show-desktop-corner";
  version = "0-unstable";

  src = lib.cleanSource (../../../../gnome + "/${uuid}");
  dontBuild = true;

  doCheck = true;
  nativeCheckInputs = [ nodejs ];
  checkPhase = ''
    runHook preCheck
    EXTENSION_DIR="$PWD" node --experimental-vm-modules --test ${../../../../gnome/tests/show-desktop-corner.test.mjs}
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/gnome-shell/extensions/${uuid}"
    cp extension.js metadata.json "$out/share/gnome-shell/extensions/${uuid}/"
    runHook postInstall
  '';

  passthru.extensionUuid = uuid;

  meta = {
    description = "Transparent bottom-right desktop toggle with fullscreen protection";
    platforms = lib.platforms.linux;
  };
}
