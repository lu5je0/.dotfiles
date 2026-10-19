{
  libcamera,
  fetchurl,
  libglvnd,
  libjpeg,
  libyuv,
  stdenv,
}:
libcamera.overrideAttrs (old: {
  version = "0.7.2-oneplus6";
  src = fetchurl {
    url = "https://github.com/libcamera-org/libcamera/archive/refs/tags/v0.7.2.tar.gz";
    hash = "sha256-7cQx6TxaQDBICgeEMASGUHZi+gvOkQ4gOlZDhhgoUo8=";
  };
  patches = (old.patches or [ ]) ++ [
    # Keep the postmarketOS 0.7.2 series in order; Quad Bayer relies on it.
    ./dmabuf-log.patch
    ./imx355-properties.patch
    ./gpu-window.patch
    ./input-format-log.patch
    ./agc-step.patch
    # postmarketOS patch 1d48b0c83e370979817ffb7e5505afbb7c7c1d47:
    # the IMX371 full-resolution stream is Quad Bayer, not ordinary Bayer.
    ./quad-bayer.patch
    ./sony-gain.patch
    # Packed RAW must be sampled at texel centres, including Quad Bayer.
    ./texel-centres.patch
    # CAMSS needs capture buffers ready before the sensor starts sending.
    ./queue-before-stream.patch
    ./imx376-pdaf.patch
    ./gpu-stats-window.patch
  ];
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];
  buildInputs = old.buildInputs ++ [
    libglvnd
    libjpeg
    libyuv
  ];
  mesonFlags = old.mesonFlags ++ [
    "-Dpipelines=simple,uvcvideo"
    "-Dipas=simple"
    "-Dsoftisp-gpu=enabled"
    "-Dcam-jpeg=enabled"
    "-Dcam-output-sdl2=disabled"
    "-Dapps-output-dng=disabled"
    "-Dlibdw=disabled"
  ];
  postInstall = (old.postInstall or "") + ''
    install -Dm644 ${./imx371.yaml} $out/share/libcamera/ipa/simple/imx371.yaml
    install -Dm644 ${./imx376.yaml} $out/share/libcamera/ipa/simple/imx376.yaml
    install -Dm644 ${./imx519.yaml} $out/share/libcamera/ipa/simple/imx519.yaml
  '';
  postBuild =
    (old.postBuild or "")
    + (
      if stdenv.buildPlatform.canExecute stdenv.hostPlatform then
        ''
          $CXX -std=c++17 -O2 -I../include/libcamera/internal/software_isp \
            ${./imx376-pdaf-test.cpp} -o imx376-pdaf-test
          ./imx376-pdaf-test
        ''
      else
        ""
    );
  meta = old.meta // {
    description = "OnePlus 6 libcamera with Sony gain models and GPU Quad Bayer processing";
    platforms = [ "aarch64-linux" ];
  };
})
