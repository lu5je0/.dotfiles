{
  lib,
  stdenv,
  src,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  autoPatchelfHook,
  cairo,
  cups,
  dbus,
  dpkg,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libnotify,
  libsecret,
  libuuid,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libXScrnSaver,
  libxtst,
  makeWrapper,
  nspr,
  nss,
  pango,
  systemd,
  wrapGAppsHook3,
  xdg-utils,
}:

stdenv.mkDerivation {
  pname = "qoder";
  version = "latest";
  inherit src;

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
    wrapGAppsHook3
  ];

  autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libnotify
    libsecret
    libuuid
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libXScrnSaver
    libxtst
    nspr
    nss
    pango
    systemd
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/opt" "$out/share"
    cp -r opt/Qoder "$out/opt/"
    cp -r usr/share/applications usr/share/icons "$out/share/"

    substituteInPlace "$out/share/applications/qoder.desktop" \
      --replace-fail "Exec=/opt/Qoder/qoder %U" "Exec=$out/bin/qoder %U"

    makeWrapper "$out/opt/Qoder/qoder" "$out/bin/qoder" \
      --prefix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --prefix LD_LIBRARY_PATH : "$out/opt/Qoder"

    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Agent workbench for human and AI software teams";
    license = lib.licenses.unfree;
    mainProgram = "qoder";
    platforms = [ "x86_64-linux" ];
  };
}
