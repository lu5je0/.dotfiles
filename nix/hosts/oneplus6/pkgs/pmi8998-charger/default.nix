{
  lib,
  stdenv,
  kernel,
}:
stdenv.mkDerivation {
  pname = "oneplus6-pmi8998-charger";
  version = kernel.version;
  src = kernel.src;
  patches = [ ./charge-behaviour.patch ];
  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  dontPatchELF = true;
  unpackPhase = ''
    runHook preUnpack
    tar xf "$src" --wildcards 'linux-*/drivers/power/supply/qcom_smbx.c' --strip-components=4
    runHook postUnpack
  '';
  buildPhase = ''
    runHook preBuild
    echo 'obj-m += qcom_smbx.o' > Makefile
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M="$PWD" -j$NIX_BUILD_CORES modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 qcom_smbx.ko \
      $out/lib/modules/${kernel.modDirVersion}/updates/qcom_smbx.ko
    runHook postInstall
  '';
  meta = {
    description = "OnePlus 6 charging inhibit control without suspending USB input";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
