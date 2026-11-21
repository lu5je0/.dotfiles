{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  fontconfig,
  libgbm,
  libpulseaudio,
  libva,
  libxcb,
  libxkbcommon,
  openssl,
  pipewire,
  wayland,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "mark-shot";
  version = "0.2.3";

  src = fetchurl {
    url = "https://github.com/jswysnemc/mark-shot/releases/download/v${finalAttrs.version}/mark-shot-native-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-2TeIw2I4ILqj661iNXsc7oPbFNBFYBeidqrxpZfHo7M=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    fontconfig
    libgbm
    libva
    libxcb
    libxkbcommon
    openssl
    pipewire
    stdenv.cc.cc.lib
  ];
  runtimeDependencies = [
    libpulseaudio
    wayland
    stdenv.cc.cc.lib
  ];
  appendRunpaths = [ "/run/opengl-driver/lib" ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -a usr/. "$out/"
    substituteInPlace "$out/share/applications/io.github.jswysnemc.MarkShot.desktop" \
      --replace-fail /usr/bin/mark-shot "$out/bin/mark-shot"
    runHook postInstall
  '';

  meta = {
    description = "Native screenshot, annotation and screen recording tool";
    homepage = "https://github.com/jswysnemc/mark-shot";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "mark-shot";
    platforms = [ "x86_64-linux" ];
  };
})
