{ python3, writeScriptBin }:
let
  python = python3.withPackages (ps: [ ps.evdev ]);
in
writeScriptBin "oneplus6-power-key" ''
  #!${python}/bin/python3
  ${builtins.readFile ./power-key.py}
''
