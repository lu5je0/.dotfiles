{
  lib,
  stdenv,
  pkg-config,
  wayland-scanner,
  wayland,
  dbus,
  libx11,
}:

let
  sourceRoot = ../../../../module/tui-bridge;
in
stdenv.mkDerivation {
  pname = "tui-bridge";
  version = lib.trim (builtins.readFile (sourceRoot + "/VERSION"));

  src = lib.fileset.toSource {
    root = sourceRoot;
    fileset =
      lib.fileset.difference
        (lib.fileset.unions [
          (sourceRoot + "/build.sh")
          (sourceRoot + "/VERSION")
          (lib.fileset.fileFilter (
            file: file.hasExt "c" || file.hasExt "h" || file.hasExt "m" || file.hasExt "xml"
          ) sourceRoot)
        ])
        (
          lib.fileset.unions [
            (lib.fileset.maybeMissing (sourceRoot + "/build"))
            (lib.fileset.maybeMissing (sourceRoot + "/linux/gen"))
            (sourceRoot + "/tests")
            (sourceRoot + "/win")
          ]
        );
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    pkg-config
    wayland-scanner
  ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    wayland
    dbus
    libx11
  ];

  buildPhase = ''
    runHook preBuild
    bash ./build.sh
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    test "$(build/tui-bridge --version)" = "$version"
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 build/tui-bridge "$out/bin/tui-bridge"
    runHook postInstall
  '';

  meta = {
    description = "跨平台 TUI 输入法与剪贴板桥接工具";
    mainProgram = "tui-bridge";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
