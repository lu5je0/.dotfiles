{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.oneplus6-charging;
  behaviour = "/sys/class/power_supply/pmi8998-charger/charge_behaviour";
  controller = pkgs.callPackage ./pkgs/charge-control { };
in
{
  options.hardware.oneplus6-charging = {
    bypassOnBoot = lib.mkEnableOption "OnePlus 6 automatic charging control at boot";
    lowerThreshold = lib.mkOption {
      type = lib.types.ints.between 1 99;
      default = 40;
      description = "Resume charging below this battery percentage.";
    };
    upperThreshold = lib.mkOption {
      type = lib.types.ints.between 1 99;
      default = 60;
      description = "Pause charging above this battery percentage.";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.lowerThreshold < cfg.upperThreshold;
        message = "OnePlus 6 lower charging threshold must be below the upper threshold.";
      }
    ];
    boot.extraModulePackages = [
      (pkgs.callPackage ./pkgs/pmi8998-charger {
        kernel = config.boot.kernelPackages.kernel;
      })
    ];

    systemd.services.oneplus6-bypass = {
      description = "Maintain OnePlus 6 battery charging in the ${toString cfg.lowerThreshold}-${toString cfg.upperThreshold} percent band";
      wantedBy = lib.optional cfg.bypassOnBoot "multi-user.target";
      after = [ "systemd-udev-trigger.service" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${controller}/bin/oneplus6-charge-control --low ${toString cfg.lowerThreshold} --high ${toString cfg.upperThreshold}";
        Restart = "on-failure";
        RestartSec = 5;
        PrivateTmp = true;
        ProtectHome = true;
        NoNewPrivileges = true;
      };
      # Restore charging on an explicit stop, failed start, or shutdown.
      postStop = ''
        if test -w ${behaviour}; then
          printf '%s\n' auto > ${behaviour}
        fi
      '';
    };
  };
}
