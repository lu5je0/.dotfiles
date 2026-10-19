{
  stdenv,
  kernel,
  dtc,
}:
stdenv.mkDerivation {
  pname = "oneplus6-camera-live-power";
  version = kernel.version;
  dontUnpack = true;
  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ dtc ];
  hardeningDisable = [ "pic" ];
  dontPatchELF = true;
  buildPhase = ''
    cp ${./overlay.c} overlay.c
    dtc -@ -I dts -O dtb -o camera.dtbo ${./live-power.dts}
    cat > overlay-data.S <<'ASM'
    .section .rodata
    .global camera_overlay_blob
    camera_overlay_blob:
    .incbin "camera.dtbo"
    .global camera_overlay_end
    camera_overlay_end:
    ASM
    cat > Makefile <<'MAKE'
    obj-m += oneplus6-camera-live-power.o
    oneplus6-camera-live-power-y := overlay.o overlay-data.o
    ccflags-y += -DCAMERA_OVERLAY_GUARD_NODE='"/soc@0/rsc@179c0000/regulators-oneplus6-camera-live"'
    MAKE
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M="$PWD" modules
  '';
  installPhase = ''
    install -Dm644 oneplus6-camera-live-power.ko \
      $out/lib/modules/${kernel.modDirVersion}/updates/oneplus6-camera-live-power.ko
  '';
}
