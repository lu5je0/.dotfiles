{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  enableDebug ? false,
}:
stdenv.mkDerivation {
  pname = "oneplus6-ath10k-wcn3990";
  version = kernel.version;
  src = kernel.src;
  patches = [
    ./wcn3990-limit-channel-width.patch
    ./wcn3990-pmf-peer-flag.patch
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  dontPatchELF = true;
  dontStrip = true;
  enableParallelBuilding = true;
  unpackPhase = ''
    runHook preUnpack
    tar xf "$src" --wildcards 'linux-*/drivers/net/wireless/ath/*' --strip-components=5
    runHook postUnpack
  '';
  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      ${lib.escapeShellArgs kernelModuleMakeFlags} \
      M="$PWD/ath10k" -j$NIX_BUILD_CORES \
      CONFIG_ATH10K=m CONFIG_ATH10K_SNOC=m CONFIG_ATH10K_PCI=n \
      CONFIG_ATH10K_AHB=n CONFIG_ATH10K_USB=n CONFIG_ATH10K_SDIO=n \
      CONFIG_ATH10K_DEBUG=${if enableDebug then "y" else "n"} \
      CONFIG_ATH10K_DEBUGFS=${if enableDebug then "y" else "n"} \
      ${lib.optionalString enableDebug "KCFLAGS='-DCONFIG_ATH10K_DEBUG -DCONFIG_ATH10K_DEBUGFS'"} modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      ${lib.escapeShellArgs kernelModuleMakeFlags} M="$PWD/ath10k" \
      INSTALL_MOD_PATH="$out" INSTALL_MOD_STRIP=1 DEPMOD=true modules_install
    runHook postInstall
  '';
  meta = {
    description = "OnePlus 6 WCN3990 driver with 80 MHz negotiation and PMF support";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
