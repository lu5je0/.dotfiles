{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    useOSProber = true;
    fsIdentifier = "provided";
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking = {
    hostName = "raider";
    networkmanager.enable = false;
    useDHCP = false;
    interfaces.ens18.ipv4.addresses = [
      {
        address = "192.168.1.3";
        prefixLength = 24;
      }
    ];
    defaultGateway = {
      address = "192.168.1.1";
      interface = "ens18";
    };
    nameservers = [ "192.168.1.1" ];
  };

  system.stateVersion = "26.05";

  # 关闭防火墙
  networking.firewall.enable = false;
}
