{
  lib,
  rustPlatform,
  stdenv,
  python3,
  trash-cli,
}:

rustPlatform.buildRustPackage {
  pname = "q-trash";
  version =
    (builtins.fromTOML (builtins.readFile ../../../../module/q-trash/Cargo.toml)).package.version;

  src = lib.fileset.toSource {
    root = ../../../../module/q-trash;
    fileset = lib.fileset.unions [
      ../../../../module/q-trash/Cargo.toml
      ../../../../module/q-trash/Cargo.lock
      ../../../../module/q-trash/build.rs
      ../../../../module/q-trash/src
      ../../../../module/q-trash/tests
    ];
  };
  cargoLock.lockFile = ../../../../module/q-trash/Cargo.lock;

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
