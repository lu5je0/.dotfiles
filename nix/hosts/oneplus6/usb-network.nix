{ ... }:
{
  # Keep a direct SSH link available even when Wi-Fi cannot connect.
  boot.kernelModules = [ "g_ether" ];
  # The legacy 0525:a4a2 ID can bind to cdc_subset on the host instead of
  # cdc_ether. Use the Linux composite gadget ID and stable local MACs.
  boot.extraModprobeConfig = ''
    options g_ether idVendor=0x1d6b idProduct=0x0104 dev_addr=02:00:00:00:06:01 host_addr=02:00:00:00:06:02
  '';
  networking.networkmanager.unmanaged = [ "interface-name:usb0" ];
  networking.interfaces.usb0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "169.254.42.1";
        prefixLength = 16;
      }
    ];
  };
}
