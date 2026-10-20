{
  lib,
  stdenv,
  fetchurl,
  kernel,
  cameraOverlay,
}:
let
  revision = "85f1df2a4ec71d7a91dd95a7a49f889d1595ffa8";
  sensor =
    name: hash:
    fetchurl {
      url = "https://gitlab.com/sdm845-mainline/linux/-/raw/${revision}/drivers/media/i2c/${name}.c";
      inherit hash;
    };
in
stdenv.mkDerivation {
  pname = "oneplus6-camera";
  version = kernel.version;
  src = kernel.src;
  patches = [
    ./01-9c51128c5f52.patch
    ./02-8e492766e84a.patch
    ./03-ee33e3de2c9d.patch
    ./04-c027f969c36d.patch
    ./05-c24292522c6f.patch
    ./06-b9b1c729eff1.patch
    ./07-51f92596d451.patch
    ./08-be47b48e94e6.patch
    ./09-f856703c060d.patch
    ./imx519-startup.patch
    ./imx519-fast-mode.patch
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  dontPatchELF = true;
  enableParallelBuilding = true;
  unpackPhase = ''
    runHook preUnpack
    tar xf "$src" --wildcards 'linux-*/drivers/media/platform/qcom/camss/*' --strip-components=1
    cp ${sensor "imx371" "sha256-3coUsLjw9jYeieoPu0R7NvQylLfgNy6nH5dwdjGw4Bg="} imx371.c
    cp ${sensor "imx376" "sha256-ta2xJTBI9iHo3z6FE7ilPi5MX9lIMcEvWIPLosR7zZQ="} imx376.c
    cp ${sensor "imx519" "sha256-DfQsunD10vsFT2eIDsWcQy9F958zgBP1wKqwcMKSQAY="} imx519.c
    cp ${sensor "lc898217xc" "sha256-ndrqix4A//d0GcVCB58br/FC8MPxh1q+0UKjIvyhZoE="} lc898217xc.c
    cp ${./overlay.c} overlay.c
    cp ${cameraOverlay} camera.dtbo
    cat > overlay-data.S <<'ASM'
    .section .rodata
    .global camera_overlay_blob
    camera_overlay_blob:
    .incbin "camera.dtbo"
    .global camera_overlay_end
    camera_overlay_end:
    ASM
    cat > Makefile <<'MAKE'
    obj-m += imx371.o imx376.o imx519.o lc898217xc.o oneplus6-camera-overlay.o
    oneplus6-camera-overlay-y := overlay.o overlay-data.o
    MAKE
    runHook postUnpack
  '';
  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M="$PWD" -j$NIX_BUILD_CORES modules
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M="$PWD/drivers/media/platform/qcom/camss" \
      -j$NIX_BUILD_CORES CONFIG_VIDEO_QCOM_CAMSS=m modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 imx371.ko imx376.ko imx519.ko lc898217xc.ko \
      oneplus6-camera-overlay.ko drivers/media/platform/qcom/camss/qcom-camss.ko \
      -t $out/lib/modules/${kernel.modDirVersion}/updates
    runHook postInstall
  '';
  meta = {
    description = "OnePlus 6 camera sensors, autofocus and CAMSS C-PHY support";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
