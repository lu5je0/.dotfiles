{ lib, pkgs, ... }:

{
  launchd.agents.nix-profile-applications.serviceConfig = {
    ProgramArguments = [
      "${pkgs.python3}/bin/python3"
      "${./sync.py}"
      (lib.getExe pkgs.rsync)
    ];
    LimitLoadToSessionType = "Aqua";
    KeepAlive = true;
  };
}
