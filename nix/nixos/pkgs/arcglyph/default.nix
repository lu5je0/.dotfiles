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

rustPlatform.buildRustPackage  {
  pname = "arcglyph";
  version = "0.7.6";

  src = fetchFromGitHub {
    owner = "lu5je0";
    repo = "arcglyph";
    rev = "85816dba3c2b1e21990fbcdbbeb24854785be6a5";
    hash = "sha256-6FbW0ZRGd3Skjms25bZfM2WDdXOLT27QVPMUD6e1r9I=";
  };

  cargoHash = "sha256-J4XQqCqcavKGs1OfXh17YeU+xBsBNtCwxjIhwkUGcfk=";

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
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          wayland
          libxkbcommon
          vulkan-loader
        ]
      }" \
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
