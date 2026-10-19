{
  pkgs,
  lib,
  runCommand,
  android-tools,
}:
let
  cross = pkgs.pkgsCross.aarch64-multiplatform;
  uboot =
    (cross.buildUBoot {
      pname = "uboot-oneplus-enchilada";
      version = "2026.07-rc1";
      src = pkgs.fetchFromGitLab {
        domain = "gitlab.postmarketos.org";
        owner = "tauchgang";
        repo = "u-boot";
        rev = "1f56592576887ffcae0e7d44c66b5cf030674908";
        hash = "sha256-A6AombRRnUaHkn7Fn7p6tkAEYnA+Z4vaJliRVB0hKuo=";
      };
      defconfig = "qcom_defconfig qcom-phone.config tauchgang.config";
      patches = [ ./extlinux.patch ];
      extraConfig = ''
        CONFIG_DEFAULT_DEVICE_TREE="qcom/sdm845-oneplus-enchilada"
        CONFIG_BOOTDELAY=5
        CONFIG_BOOTMETH_EXTLINUX=y
        CONFIG_CMD_SYSBOOT=y
      '';
      filesToInstall = [
        "u-boot-nodtb.bin"
        "u-boot.dtb"
      ];
      extraMeta.platforms = [ "aarch64-linux" ];
    }).overrideAttrs
      (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.unixtools.xxd ];
      });
in
runCommand "uboot-oneplus-enchilada-android-image"
  {
    nativeBuildInputs = [ android-tools ];
    meta = {
      description = "OnePlus 6 U-Boot Android boot image";
      license = lib.licenses.gpl2Plus;
      platforms = [ "x86_64-linux" ];
    };
  }
  ''
    gzip -c ${uboot}/u-boot-nodtb.bin > u-boot.bin.gz
    cat u-boot.bin.gz ${uboot}/u-boot.dtb > u-boot-with-dtb.bin.gz
    printf '\0' | gzip -c > empty.gz
    mkbootimg --base 0 --kernel_offset 0x8000 --pagesize 4096 \
      --kernel u-boot-with-dtb.bin.gz --ramdisk empty.gz -o $out
  ''
