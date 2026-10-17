{
  runCommand,
  dtc,
  kernel,
}:
runCommand "oneplus6-device-tree" { nativeBuildInputs = [ dtc ]; } ''
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
''
