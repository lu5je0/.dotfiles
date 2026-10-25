{
  ddcci-driver,
  python3,
}:

ddcci-driver.overrideAttrs (oldAttrs: {
  # workaround: huskar-ddcci-brightness-write-confirmation
  patches = (oldAttrs.patches or [ ]) ++ [
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
