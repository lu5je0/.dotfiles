{
  runCommand,
  stdenv,
  dtc,
  kernel,
}:
runCommand "oneplus6-device-tree"
  {
    nativeBuildInputs = [
      dtc
      stdenv.cc
    ];
  }
  ''
    mkdir -p $out/qcom
    dtb=$out/qcom/sdm845-oneplus-enchilada.dtb
    cp ${kernel}/dtbs/qcom/sdm845-oneplus-enchilada.dtb "$dtb"
    chmod u+w "$dtb"

    # Android 11 firmware owns PM8998 GPIO3. It is already configured as
    # SW_CTRL input; attempting to reconfigure it returns EPERM and prevents
    # the WCN3990 power sequencer (and therefore Wi-Fi) from probing.
    # The 7.2 power sequencer does not consume swctrl-gpios itself.
    fdtput -d "$dtb" /wcn3990-pmu pinctrl-0
    fdtput -d "$dtb" /wcn3990-pmu pinctrl-names
    test "$(fdtget -t s "$dtb" /wcn3990-pmu compatible)" = qcom,wcn3990-pmu

    mkdir -p include $out/overlays
    tar xf ${kernel.src} -C include --wildcards \
      'linux-*/include/dt-bindings/*' --strip-components=2
    cc -E -P -x assembler-with-cpp -nostdinc -undef -I include \
      ${./camera.dts} > camera.dts
    dtc -@ -I dts -O dtb -o $out/overlays/oneplus6-camera.dtbo camera.dts
    fdtoverlay -i "$dtb" -o camera.dtb $out/overlays/oneplus6-camera.dtbo
    mv camera.dtb "$dtb"
    test "$(fdtget -t s "$dtb" /soc@0/camss@acb3000 status)" = okay
  ''
