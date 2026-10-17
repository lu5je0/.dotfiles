{ writeScriptBin, python3 }:
writeScriptBin "oneplus6-bluetooth-address" (
  "#!${python3}/bin/python3\n" + builtins.readFile ./bluetooth-address.py
)
