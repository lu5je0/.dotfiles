{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./audio.nix
    ./charging.nix
    ./power.nix
    ./qualcomm.nix
    ./usb-network.nix
  ];

  hardware.oneplus6-charging = {
    bypassOnBoot = true;
    lowerThreshold = 40;
    upperThreshold = 60;
  };

  networking = {
    hostName = "oneplus6";
    networkmanager.enable = true;
    networkmanager.wifi.macAddress = "stable";
    modemmanager.enable = false;
  };
  services.avahi = {
    enable = true;
    publish.enable = true;
    publish.addresses = true;
    openFirewall = true;
  };
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };
  users.users.lu5je0 = {
    hashedPasswordFile = "/var/lib/nixos/secrets/oneplus6-user-password";
    openssh.authorizedKeys.keyFiles = [ ./authorized-key.pub ];
    extraGroups = [
      "video"
      "input"
      "dialout"
    ];
  };

  environment.systemPackages = [
    pkgs.gnome-console
    pkgs.iw
  ];
  system.stateVersion = "26.05";
}
