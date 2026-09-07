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

  networking.hostName = "nixpve";
  networking.networkmanager.enable = true;

  system.stateVersion = "26.05";
}
