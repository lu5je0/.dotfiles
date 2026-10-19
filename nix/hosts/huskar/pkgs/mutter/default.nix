{ mutter }:

mutter.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [ ./backlight-dpms.patch ];
})
