{ python3, writeScriptBin }:
writeScriptBin "oneplus6-charge-control" ''
  #!${python3}/bin/python3
  ${builtins.readFile ./charge-control.py}
''
