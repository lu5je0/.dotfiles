{
  lib,
  stdenvNoCC,
  fetchFromGitLab,
  fetchpatch,
}:

stdenvNoCC.mkDerivation {
  pname = "oneplus-sdm845-firmware";
  version = "0-unstable-2026-04-28";

  src = fetchFromGitLab {
    name = "oneplus-sdm845-firmware-source";
    owner = "sdm845-mainline";
    repo = "firmware-oneplus-sdm845";
    rev = "3e31a0c3e5a061645c09f805387b49fa9d35acbf";
    hash = "sha256-DeOlhchDGi0Pso3w8ZlM7q3Tdkmt3Ji+GyEmepkISTE=";
  };

  patches = [
    # See <https://gitlab.com/sdm845-mainline/firmware-oneplus-sdm845/-/merge_requests/3>.
    (fetchpatch {
      name = "0001-oneplus6-set-mount-matrix.patch";
      url = "https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/1b853b79baecb837f53504a5bc947d3130bcaaa6/device/community/firmware-oneplus-sdm845/0001-oneplus6-set-mount-matrix.patch?inline=false";
      hash = "sha256-kuxEve7dTBH78ojp02P5RECSnitf8Ns6/DR1ikCLuJo=";
    })
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    while IFS="" read -r _i || [ -n "$_i" ]; do
      install -Dm644 "$_i" "$out/''${_i/"postmarketos"/}"
    done < "${./firmware.files}"

    # Files to be included to add sensor support.
    while IFS="" read -r _i || [ -n "$_i" ]; do
      install -Dm644 "$_i" "$out/''${_i#"./usr"}"
    done < "${./sensor.files}"

    ln -s oneplus6 $out/share/qcom/sdm845/OnePlus/enchilada
    ln -s oneplus6 $out/share/qcom/sdm845/OnePlus/fajita

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    firmwareDir="$out/lib/firmware/qcom/sdm845/OnePlus/enchilada"
    printf '%s\n' \
      "d7387fe1d377e7fe98a77fc8dd83690bfaaa3abe79623360285ddd8ee4184b5c  $firmwareDir/modem.mbn" \
      "d7be2977263061155b2694a140548783f7cd40108cc72b7816a3ef41b95dc923  $firmwareDir/adsp.mbn" |
      sha256sum --strict --check

    runHook postInstallCheck
  '';

  dontFixup = true;

  meta = {
    description = "Firmware for OnePlus 6 / 6T";
    homepage = "https://gitlab.com/sdm845-mainline/firmware-oneplus-sdm845";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ kwaa ];
    platforms = lib.platforms.all;
    # Lower numbers win in hardware.firmware's buildEnv. The device-specific
    # crbtfw21.tlv must override linux-firmware (priority 6), otherwise the
    # WCN3990 controller times out on HCI Reset after downloading firmware.
    priority = 5;
  };
}
