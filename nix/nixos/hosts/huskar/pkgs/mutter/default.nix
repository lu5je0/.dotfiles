{ mutter }:

mutter.overrideAttrs (oldAttrs: {
  # workaround: huskar-mutter-dpms-backlight
  patches = (oldAttrs.patches or [ ]) ++ [ ./backlight-dpms.patch ];
})
