{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  # ── Chromium / Electron 运行时依赖 ──
  alsa-lib,
  at-spi2-core, # libatk-1.0 / libatk-bridge-2.0 / libatspi
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libgbm, # mesa 26 起从 mesa 拆出
  libglvnd,
  libnotify,
  libpulseaudio,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libXScrnSaver, # libXss.so.1
  libxtst,
  nspr,
  nss,
  pango,
  pipewire,
  systemd, # libudev
  vulkan-loader,
  xdg-utils,
}:

let
  version = "0.11.1";

  releases = {
    x86_64-linux = {
      target = "linux-x64";
      hash = "sha256-sIMnZVqjGQJgzzSAcpS+fHxmhaomOaOTBVt8ZJ7rOko=";
    };
  };

  release =
    releases.${stdenv.hostPlatform.system}
      or (throw "terminal-browser: unsupported system ${stdenv.hostPlatform.system}");

  runtimeLibraries = [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libgbm
    libglvnd
    libnotify
    libpulseaudio
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
    pipewire
    stdenv.cc.cc.lib
    systemd
    vulkan-loader
  ];
in
stdenv.mkDerivation {
  pname = "terminal-browser";
  inherit version;

  src = fetchurl {
    url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${version}/terminal-browser-${release.target}.tar.gz";
    inherit (release) hash;
  };

  # tarball 根目录就叫 terminal-browser/
  sourceRoot = "terminal-browser";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = runtimeLibraries;

  # 目录里全是官方预编译产物（electron/pixel、agent-browser、pixel.node），
  # strip 既慢又没有意义，还可能破坏 Electron 自带符号。
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/bin"
    cp -R . "$out/lib/terminal-browser"

    # electron/pixel 自带 RPATH=$ORIGIN（找同目录的 libffmpeg.so），
    # autoPatchelfHook 会保留它；这里只额外补 GPU 驱动目录。
    makeWrapper "$out/lib/terminal-browser/bin/terminal-browser" "$out/bin/terminal-browser" \
      --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib" \
      --prefix PATH : "${lib.makeBinPath [ xdg-utils ]}"

    runHook postInstall
  '';

  meta = {
    description = "Real browser that runs inside your terminal";
    homepage = "https://terminal-browser.sh";
    changelog = "https://github.com/zenbu-labs/terminal-browser/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "terminal-browser";
    platforms = builtins.attrNames releases;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
