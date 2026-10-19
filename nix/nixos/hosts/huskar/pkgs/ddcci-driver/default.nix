{
  ddcci-driver,
  fetchpatch,
  python3,
}:

ddcci-driver.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [
    # Linux 7.2 移除了 strncpy；上游 MR !21 改用 sysfs_emit 输出设备属性。
    # https://gitlab.com/ddcci-driver-linux/ddcci-driver-linux/-/merge_requests/21
    (fetchpatch {
      name = "ddcci-linux-7.2-sysfs-emit.patch";
      url = "https://gitlab.com/liquidnya/ddcci-driver-linux/-/commit/9510aa4aebf32678884f55ae251e54012a354ed1.patch";
      hash = "sha256-s12ers7nPFaHOB+8/S8t3dtdoR6slukkfNPdghgftNs=";
    })
    ./brightness-write-retry.patch
  ];

  doCheck = true;
  nativeCheckInputs = (oldAttrs.nativeCheckInputs or [ ]) ++ [ python3 ];
  checkPhase = ''
    runHook preCheck
    python3 ${./test_brightness.py} ddcci-backlight/ddcci-backlight.c
    runHook postCheck
  '';
})
