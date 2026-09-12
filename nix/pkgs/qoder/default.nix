{
  lib,
  stdenv,
  fetchurl,
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
  libglvnd,
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
  version = "0.2.3";
  src = fetchurl {
    url = "https://download.qoder.com/qoder-app/releases/latest/Qoder-linux-amd64.deb";
    hash = "sha256-A/qDXBGFrn5tX8JW4sH70mGxRb1eTxtAV8QmMxewSx0=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
    wrapGAppsHook3
  ];

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
    libglvnd
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

  postUnpack = ''
    rm -rf \
      opt/Qoder/resources/app.asar.unpacked/node_modules/@img/sharp-linuxmusl-x64 \
      opt/Qoder/resources/app.asar.unpacked/node_modules/@img/sharp-libvips-linuxmusl-x64
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/opt" "$out/share"
    cp -r opt/Qoder "$out/opt/"
    cp -r usr/share/applications usr/share/icons "$out/share/"

    substituteInPlace "$out/share/applications/qoder.desktop" \
      --replace-fail "Exec=/opt/Qoder/qoder %U" "Exec=$out/bin/qoder --ozone-platform=wayland %U"

    makeWrapper "$out/opt/Qoder/qoder" "$out/bin/qoder" \
      --prefix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --prefix LD_LIBRARY_PATH : "$out/opt/Qoder:${lib.makeLibraryPath [ libgbm libglvnd libsecret ]}:/run/opengl-driver/lib" \
      --add-flags "--ozone-platform=wayland" \
      --add-flags "--enable-features=WaylandWindowDecorations" \
      --add-flags "--password-store=gnome-libsecret" \
      --add-flags "--use-gl=angle" \
      --add-flags "--use-angle=gl"

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
