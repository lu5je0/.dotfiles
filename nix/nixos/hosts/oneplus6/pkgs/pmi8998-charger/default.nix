{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:
stdenv.mkDerivation {
  pname = "oneplus6-pmi8998-charger";
  version = kernel.version;
  src = kernel.src;
  patches = [ ./charge-behaviour.patch ];
  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  dontPatchELF = true;
  dontStrip = true;
  unpackPhase = ''
    runHook preUnpack
    tar xf "$src" --wildcards 'linux-*/drivers/power/supply/qcom_smbx.c' --strip-components=4
    runHook postUnpack
  '';
  buildPhase = ''
    runHook preBuild
    echo 'obj-m += qcom_smbx.o' > Makefile
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      ${lib.escapeShellArgs kernelModuleMakeFlags} M="$PWD" -j$NIX_BUILD_CORES modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      ${lib.escapeShellArgs kernelModuleMakeFlags} M="$PWD" \
      INSTALL_MOD_PATH="$out" INSTALL_MOD_STRIP=1 DEPMOD=true modules_install
    runHook postInstall
  '';
  meta = {
    description = "OnePlus 6 charging inhibit control without suspending USB input";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
