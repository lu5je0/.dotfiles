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
  version = "0.49.0-unstable-2026-09-22";
  src = fetchFromGitHub {
    owner = "lu5je0";
    repo = "kitty";
    rev = "260df2d2c4281a75160ff6dc65e8a7aabbea000d";
    hash = "sha256-Uv8fEZgYvVO4/NsBckK3TXCKIxmL0BF5nrNWDAblAgc=";
  };
in
kitty.overrideAttrs (old: {
  pname = "kitty-lu5je0";
  inherit src version;

  goModules =
    (buildGo126Module {
      pname = "kitty-lu5je0-go-modules";
      inherit src version;
      vendorHash = "sha256-G+eaFOFMIIu2Qo5Mgr3ejwoYrYmNv3EIdEEraDPIdeY=";
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
