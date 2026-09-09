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
  vulkan-loader,
  noto-fonts-cjk-sans-static,
}:

rustPlatform.buildRustPackage rec {
  pname = "arcglyph";
  version = "0.7.0";

  src = fetchFromGitHub {
    owner = "lu5je0";
    repo = "arcglyph";
    rev = "91128be01aab6b084e4d134b05c7f16f2727d927";
    hash = "sha256-unVYFie20Qyya43JRGFwQWQ+czi1BeCe9iemDPt+Ci8=";
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
    vulkan-loader
  ];

  postInstall = ''
    install -Dm644 packaging/arcglyph.desktop \
      "$out/share/applications/arcglyph.desktop"
    install -Dm644 packaging/60-arcglyph-uinput.rules \
      "$out/lib/udev/rules.d/60-arcglyph-uinput.rules"
  '';

  postFixup = ''
    wrapProgram "$out/bin/arcglyph" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ wayland libxkbcommon vulkan-loader ]}" \
      --set ARCGLYPH_FONT "${noto-fonts-cjk-sans-static}/share/fonts/opentype/noto-cjk/NotoSansCJK-Regular.ttc"
  '';

  meta = {
    description = "Right-click mouse-gesture daemon for Wayland";
    homepage = "https://github.com/lu5je0/arcglyph";
    license = lib.licenses.mit;
    mainProgram = "arcglyph";
    platforms = lib.platforms.linux;
  };
}
