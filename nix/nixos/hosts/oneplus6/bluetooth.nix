{ pkgs, ... }:
let
  address = pkgs.callPackage ./pkgs/bluetooth-address { };
in
{
  # The WCN3990 NVM has a placeholder address. Configure it before BlueZ
  # starts, otherwise Linux exposes only an unconfigured HCI controller.
  systemd.services.oneplus6-bluetooth-address = {
    description = "Configure the OnePlus 6 Bluetooth controller address";
    wantedBy = [ "bluetooth.service" ];
    before = [ "bluetooth.service" ];
    after = [ "systemd-udev-trigger.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${address}/bin/oneplus6-bluetooth-address --btmgmt ${pkgs.bluez}/bin/btmgmt";
      TimeoutStartSec = 45;
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };
}
