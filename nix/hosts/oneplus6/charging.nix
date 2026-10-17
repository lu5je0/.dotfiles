{
  config,
  lib,
  pkgs,
  ...
}:
let
  behaviour = "/sys/class/power_supply/pmi8998-charger/charge_behaviour";
in
{
  options.hardware.oneplus6-charging.bypassOnBoot = lib.mkEnableOption "OnePlus 6 charging bypass at boot";

  config = {
    boot.extraModulePackages = [
      (pkgs.callPackage ./pkgs/pmi8998-charger {
        kernel = config.boot.kernelPackages.kernel;
      })
    ];

    systemd.services.oneplus6-bypass = {
      description = "Pause OnePlus 6 battery charging while retaining USB input";
      wantedBy = lib.optional config.hardware.oneplus6-charging.bypassOnBoot "multi-user.target";
      after = [ "systemd-udev-trigger.service" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 30;
        PrivateTmp = true;
        ProtectHome = true;
        NoNewPrivileges = true;
      };
      script = ''
        for attempt in $(seq 1 100); do
          if test -w ${behaviour}; then
            break
          fi
          sleep 0.2
        done
        if ! test -w ${behaviour}; then
          echo "PMI8998 charge_behaviour is unavailable; check the patched qcom_smbx module" >&2
          exit 1
        fi
        printf '%s\n' inhibit-charge > ${behaviour}
        cat ${behaviour}
      '';
      # Restore charging on an explicit stop, failed start, or shutdown.
      postStop = ''
        if test -w ${behaviour}; then
          printf '%s\n' auto > ${behaviour}
        fi
      '';
    };
  };
}
