{
  lib,
  stdenv,
  pkg-config,
  libevdev,
  systemd,
  kernel,
  kernelModuleMakeFlags,
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
    dontStrip = true;
    enableParallelBuilding = true;
    makeFlags = kernelModuleMakeFlags ++ [
      "-C"
      "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "M=$(PWD)"
      "INSTALL_MOD_PATH=$(out)"
      "INSTALL_MOD_DIR=extra"
      "CONFIG_MODULE_COMPRESS_ALL="
    ];
    buildFlags = [ "modules" ];
    # modules_install 通过内核签名规则生成模块及汇总所需的 .ko.cer。
    installTargets = [ "modules_install" ];
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
