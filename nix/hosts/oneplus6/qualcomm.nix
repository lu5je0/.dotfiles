{ pkgs, ... }:
{
  # WLAN firmware runs alongside the modem remote processor. Disabling the
  # modem driver also prevents ath10k_snoc from discovering its QMI service.
  # These are ordinary nixpkgs programs; no Mobile NixOS module is required.
  systemd.services.rmtfs = {
    description = "Qualcomm remote filesystem service";
    wantedBy = [ "multi-user.target" ];
    # On shutdown, disconnect WLAN before rmtfs stops the shared remoteproc.
    before = [
      "NetworkManager.service"
      "wpa_supplicant.service"
    ];
    serviceConfig = {
      # Keep device-specific modem NV partitions read-only.
      ExecStart = "${pkgs.rmtfs}/bin/rmtfs -s -r -P";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  systemd.services.tqftpserv = {
    description = "Qualcomm firmware transfer service";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tqftpserv}/bin/tqftpserv";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  services.udev.extraRules = ''
    SUBSYSTEM=="uio", ATTR{name}=="rmtfs", SYMLINK+="qcom_rmtfs_uio1"
  '';
}
