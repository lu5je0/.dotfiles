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
  version = "0.49.2-unstable-2026-10-07";
  src = fetchFromGitHub {
    owner = "lu5je0";
    repo = "kitty";
    rev = "b9789aca540a324b9d1e7f5a55a94f9cb07befe0";
    hash = "sha256-aFkRSsOjTuDnk4K4kyZ7Er0nN2qYnWday8GNfqN3lQw=";
  };
in
kitty.overrideAttrs (old: {
  pname = "kitty-lu5je0";
  inherit src version;

  goModules =
    (buildGo126Module {
      pname = "kitty-lu5je0-go-modules";
      inherit src version;
      vendorHash = "sha256-iSPPwwu9jllnIxkQeOlJFdDL4xLUGRP2RMW9DPRY6FQ=";
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
