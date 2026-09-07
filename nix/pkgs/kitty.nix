{
  buildGo126Module,
  fetchFromGitHub,
  kitty,
  lib,
  libxkbcommon,
  python3Packages,
  shader-slang,
}:

let
  version = "0.48.2-unstable-2026-08-29";
  src = fetchFromGitHub {
    owner = "lu5je0";
    repo = "kitty";
    rev = "cb5587f4326c288629c39447b8670aae80e300bd";
    hash = "sha256-jioUP/zqp8SSyvvNR1c8EDw3VQGqAzx+vlyvLm2IXiU=";
  };
in
kitty.overrideAttrs (old: {
  pname = "kitty-lu5je0";
  inherit src version;

  goModules = (buildGo126Module {
    pname = "kitty-lu5je0-go-modules";
    inherit src version;
    vendorHash = "sha256-TkyiG0Yu8W5OV7g+TlL1+IZEbhVR8/ybb9WL4CIhozU=";
  }).goModules;

  nativeBuildInputs = old.nativeBuildInputs ++ [
    python3Packages.sphinx-design
    shader-slang
  ];

  patches = builtins.filter (
    patch: !(lib.hasSuffix "libxkbcommon-runtime-path.patch" (toString patch))
  ) old.patches;

  postPatch = (old.postPatch or "") + ''
    substituteInPlace kitty/key_names.py \
      --replace-fail "lib = ctypes.CDLL(f'libxkbcommon.so{suffix}')" \
        "lib = ctypes.CDLL('${lib.getLib libxkbcommon}/lib/libxkbcommon.so.0')"
  '';

  meta = old.meta // {
    description = "Kitty terminal with lu5je0's custom features";
    homepage = "https://github.com/lu5je0/kitty";
  };
})
