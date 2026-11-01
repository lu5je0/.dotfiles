{
  lib,
  stdenv,
  pkg-config,
  libevdev,
  systemd,
  kernel,
}:
let
  kernelModule = stdenv.mkDerivation {
    pname = "jerry-fn-ctrl-ec";
    version = kernel.version;
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./Makefile
        ./fn_ctrl_ec.c
      ];
    };
    nativeBuildInputs = kernel.moduleBuildDependencies;
    hardeningDisable = [ "pic" ];
    dontPatchELF = true;
    buildPhase = ''
      runHook preBuild
      make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
        M="$PWD" -j$NIX_BUILD_CORES modules
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm644 fn_ctrl_ec.ko \
        $out/lib/modules/${kernel.modDirVersion}/extra/fn_ctrl_ec.ko
      runHook postInstall
    '';
    meta = {
      description = "Read-only Fn state for Lenovo 82DM F0CN35WW";
      license = lib.licenses.gpl2Only;
      platforms = [ "x86_64-linux" ];
    };
  };
in
stdenv.mkDerivation {
  pname = "jerry-fn-ctrl";
  version = "1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./fn-ctrl.c
      ./state.h
      ./test-state.c
    ];
  };
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    libevdev
    systemd
  ];
  dontUseMake = true;
  buildPhase = ''
    runHook preBuild
    $CC -std=c11 -O2 -Wall -Wextra -Werror fn-ctrl.c -o fn-ctrl \
      $(pkg-config --cflags --libs libevdev libsystemd)
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    $CC -std=c11 -O2 -Wall -Wextra -Werror test-state.c -o test-state
    ./test-state
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 fn-ctrl $out/bin/fn-ctrl
    runHook postInstall
  '';
  passthru = { inherit kernelModule; };
  meta = {
    description = "Fn to Ctrl input bridge for jerry";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "fn-ctrl";
  };
}
