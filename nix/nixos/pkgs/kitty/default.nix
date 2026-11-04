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
  version = "0.50.0-unstable-2026-11-04";
  src = fetchFromGitHub {
    owner = "lu5je0";
    repo = "kitty";
    rev = "9ddc8edce309553435639f7fc45fc5e181132914";
    hash = "sha256-YsWDQfBTRAFS7slK7nsyRfEns4dM4mDIsa3UN+Y/bDA=";
  };
in
kitty.overrideAttrs (old: {
  pname = "kitty-lu5je0";
  inherit src version;

  goModules =
    (buildGo126Module {
      pname = "kitty-lu5je0-go-modules";
      inherit src version;
      vendorHash = "sha256-Oo5ehjdq4HcTxZcKi/rwz8dDZYGxdSS8cqIkbdLBrb8=";
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
