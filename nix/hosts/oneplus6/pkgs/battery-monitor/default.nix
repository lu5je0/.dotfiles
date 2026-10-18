{ python3, writeTextFile }:
writeTextFile {
  name = "oneplus6-battery-monitor";
  destination = "/bin/oneplus6-battery-monitor";
  executable = true;
  text = builtins.replaceStrings [ "#!/usr/bin/env python3" ] [ "#!${python3}/bin/python3" ] (
    builtins.readFile ./battery_monitor.py
  );
  checkPhase = ''
    ${python3}/bin/python3 -B -m unittest discover -v -s ${./.}
  '';
}
