{ pkgs, ... }:
let
  monitor = pkgs.callPackage ./. { };
in
{
  system.build.oneplus6-battery-monitor = monitor;

  users.groups.oneplus6-battery-monitor = { };
  users.users.oneplus6-battery-monitor = {
    isSystemUser = true;
    group = "oneplus6-battery-monitor";
    description = "OnePlus 6 battery recorder";
  };

  systemd.services.oneplus6-battery-monitor = {
    description = "Record OnePlus 6 battery samples with 30-day retention";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-trigger.service" ];
    serviceConfig = {
      ExecStart = "${monitor}/bin/oneplus6-battery-monitor --directory /var/lib/oneplus6-battery-monitor --interval 60 --retention-days 30";
      Restart = "always";
      RestartSec = 10;
      User = "oneplus6-battery-monitor";
      Group = "oneplus6-battery-monitor";
      StateDirectory = "oneplus6-battery-monitor";
      StateDirectoryMode = "0755";
      UMask = "0022";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
