{
  lib,
  rustPlatform,
  stdenv,
  python3,
  trash-cli,
}:

let
  sourceRoot = ../../../../module/q-trash;
in
rustPlatform.buildRustPackage {
  pname = "q-trash";
  version = (builtins.fromTOML (builtins.readFile (sourceRoot + "/Cargo.toml"))).package.version;

  src = lib.fileset.toSource {
    root = sourceRoot;
    fileset = lib.fileset.unions [
      (sourceRoot + "/Cargo.toml")
      (sourceRoot + "/Cargo.lock")
      (sourceRoot + "/build.rs")
      (sourceRoot + "/src")
      (sourceRoot + "/tests")
    ];
  };
  cargoLock.lockFile = sourceRoot + "/Cargo.lock";

  nativeCheckInputs = lib.optionals stdenv.hostPlatform.isLinux [
    (python3.withPackages (ps: [ ps.pytest ]))
    trash-cli
  ];
  # Foundation trash operations need a real user session outside the Nix sandbox.
  postCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export QTRASH_BIN="$PWD/target/${stdenv.hostPlatform.rust.rustcTarget}/release/q-trash"
    python3 tests/run_compare.py
    python3 tests/run_qtrash.py
    python3 tests/run_safety.py
    python3 -m pytest tests/test_qrm.py -q
  '';

  meta = {
    description = "跨平台回收站与 rm 兼容命令";
    mainProgram = "q-trash";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
