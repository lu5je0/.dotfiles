{
  lib,
  stdenv,
  kernel,
  enableDebug ? false,
}:
stdenv.mkDerivation {
  pname = "oneplus6-ath10k-wcn3990";
  version = kernel.version;
  src = kernel.src;
  patches = [ ./wcn3990-limit-channel-width.patch ];
  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  dontPatchELF = true;
  enableParallelBuilding = true;
  unpackPhase = ''
    runHook preUnpack
    tar xf "$src" --wildcards 'linux-*/drivers/net/wireless/ath/*' --strip-components=5
    runHook postUnpack
  '';
  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
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
    install -Dm644 ath10k/ath10k_core.ko ath10k/ath10k_snoc.ko \
      -t $out/lib/modules/${kernel.modDirVersion}/updates
    runHook postInstall
  '';
  meta = {
    description = "OnePlus 6 WCN3990 driver with working 80 MHz negotiation";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
