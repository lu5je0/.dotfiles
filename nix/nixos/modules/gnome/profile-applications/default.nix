{
  config,
  lib,
  pkgs,
  ...
}:

let
  excluded = pkgs.writeText "nix-profile-applications-excluded.json" (
    builtins.toJSON (
      map (name: if lib.hasSuffix ".desktop" name then name else "${name}.desktop") (
        builtins.attrNames (config.programs.desktopIconOverrides or { })
      )
    )
  );
in
{
  systemd.user.paths.nix-profile-applications = {
    description = "Watch Nix user profile switches for desktop applications";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    pathConfig = {
      # Watch the real parent directories, not an immutable generation's share directory.
      PathChanged = [
        "%S/nix/profiles"
        "/nix/var/nix/profiles/per-user/%u"
        "%h"
        "/nix/var/nix/profiles"
        "/run"
        "/etc/profiles"
        "/etc/profiles/per-user"
      ];
      Unit = "nix-profile-applications.service";
    };
  };

  systemd.user.services.nix-profile-applications = {
    description = "Synchronize Nix profile application launchers and icons";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session-pre.target" ];
    before = [ "desktop-icon-overrides.service" ];
    # Parent directories also emit unrelated events; unchanged profiles exit immediately.
    startLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        "${pkgs.python3}/bin/python3 ${./sync.py} --exclude ${excluded}"
        + " --desktop-database ${pkgs.desktop-file-utils}/bin/update-desktop-database"
        + lib.optionalString (
          config.programs ? desktopIconOverrides
        ) " --systemctl ${pkgs.systemd}/bin/systemctl";
    };
  };
}
