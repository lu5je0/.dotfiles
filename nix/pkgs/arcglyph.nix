{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  dbus,
  fontconfig,
  wayland,
  libxkbcommon,
}:

rustPlatform.buildRustPackage rec {
  pname = "arcglyph";
  version = "0.7.0";

  src = fetchFromGitHub {
    owner = "lu5je0";
    repo = "arcglyph";
    rev = "73431b2158448e81a194ec904505f927aadc52a0";
    hash = "sha256-h0x+x4OEZkXWNaNQKfgaeAMj5baR5FK2wGLMVOCgNic=";
  };

  cargoHash = "sha256-E3mH1qd5onvskZBK0eIKfngx6sNM8D3tHGppIWunNU0=";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    dbus
    fontconfig
    wayland
    libxkbcommon
  ];

  postInstall = ''
    install -Dm644 packaging/arcglyph.desktop \
      "$out/share/applications/arcglyph.desktop"
    install -Dm644 packaging/60-arcglyph-uinput.rules \
      "$out/lib/udev/rules.d/60-arcglyph-uinput.rules"
  '';

  postFixup = ''
    wrapProgram "$out/bin/arcglyph" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ wayland libxkbcommon ]}"
  '';

  meta = {
    description = "Right-click mouse-gesture daemon for Wayland";
    homepage = "https://github.com/lu5je0/arcglyph";
    license = lib.licenses.mit;
    mainProgram = "arcglyph";
    platforms = lib.platforms.linux;
  };
}
