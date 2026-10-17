{ pkgs, ... }:
{
  # Stock 7.2 enters s2idle on a power-key press but does not resume on this phone.
  # Keep the system running while the locked panel is off until resume is fixed.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };
  services.logind.settings.Login.HandlePowerKey = "ignore";

  programs.dconf.profiles = builtins.listToAttrs (
    map
      (name: {
        inherit name;
        value.databases = [
          {
            settings."org/gnome/settings-daemon/plugins/power" = {
              power-button-action = "nothing";
              sleep-inactive-ac-type = "nothing";
              sleep-inactive-battery-type = "nothing";
            };
          }
        ];
      })
      [
        "user"
        "gdm"
      ]
  );

  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="pm8941_pwrkey", SYMLINK+="input/oneplus6-power"
  '';
  systemd.services.oneplus6-power-key = {
    description = "OnePlus 6 lock, blank and wake power key";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-trigger.service" ];
    path = [
      pkgs.systemd
      pkgs.util-linux
      pkgs.coreutils
    ];
    serviceConfig = {
      ExecStart = "${pkgs.callPackage ./pkgs/power-key { }}/bin/oneplus6-power-key";
      Restart = "on-failure";
      RestartSec = 2;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };
  };
}
