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
  version = "0.7.4";

  src = fetchFromGitHub {
    owner = "lu5je0";
    repo = "arcglyph";
    rev = "d9d98af427d5dd4679cc7cda3bfb60d9fd09ceef";
    hash = "sha256-h8najBLg5zN8UjlAGFpSH8XBy9O25RucSB6tsjtpYjE=";
  };

  cargoHash = "sha256-IQhRf5SuGwjgMQgBZEkQFVqwY2NQHmxqBGGL4P+bsaw=";

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
