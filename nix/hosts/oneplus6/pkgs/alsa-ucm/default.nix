{
  lib,
  stdenvNoCC,
  fetchFromGitLab,
}:
stdenvNoCC.mkDerivation {
  pname = "oneplus6-alsa-ucm";
  version = "0-unstable-2026-05-07";

  src = fetchFromGitLab {
    owner = "sdm845-mainline";
    repo = "alsa-ucm-conf";
    rev = "628b9900cdd2b9b8356201293f1da5396cf0ca27";
    hash = "sha256-8RvxmqD7zU/kZO7AYU/XOf9nXKewM8vAHordJfSvwS4=";
  };

  # The stock kernel provides multimedia audio, without downstream Q6Voice controls.
  patches = [ ./mainline.patch ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/alsa
    cp -r ucm2 $out/share/alsa/
    runHook postInstall
  '';

  meta = {
    description = "OnePlus 6 ALSA routes for the mainline SDM845 audio driver";
    homepage = "https://gitlab.com/sdm845-mainline/alsa-ucm-conf";
    license = lib.licenses.bsd3;
    platforms = [ "aarch64-linux" ];
  };
}
