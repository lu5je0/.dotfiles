{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation {
  pname = "pingfang";
  version = "20.0d4e1";

  src = fetchurl {
    url = "https://updates.cdn-apple.com/2024/mobileassets/062-14283/992898D8-65BC-436B-B9F9-EB2D576A24BC/com_apple_MobileAsset_Font7/3419f2a427639ad8c8e139149a287865a90fa17e.zip";
    hash = "sha256-QAZsX3MmX2+g5RN9TMr+q8LxZTr6hMTuCMYINAm1AmE=";
  };

  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/fonts/truetype"
    unzip -j "$src" AssetData/PingFang.ttc -d "$out/share/fonts/truetype"
    runHook postInstall
  '';

  meta.license = lib.licenses.unfree;
}
