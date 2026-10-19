{ config, pkgs, ... }:
let
  kernel = config.boot.kernelPackages.kernel;
  tree = pkgs.callPackage ./pkgs/device-tree { inherit kernel; };
  drivers = pkgs.callPackage ./pkgs/camera {
    inherit kernel;
    cameraOverlay = "${tree}/overlays/oneplus6-camera.dtbo";
  };
  cameraLib = pkgs.callPackage ./pkgs/libcamera { };
  cameraPipewire = pkgs.callPackage ./pkgs/pipewire-camera { libcamera = cameraLib; };
in
{
  nixpkgs.overlays = [
    (_final: prev: {
      snapshot = prev.callPackage ./pkgs/snapshot {
        baseSnapshot = prev.snapshot;
        inherit cameraLib cameraPipewire;
      };
    })
  ];
  boot.extraModulePackages = [ drivers ];
  system.build.oneplus6-camera = drivers;
  system.build.oneplus6-libcamera = cameraLib;
  # Optional live diagnostics; never loaded at boot.
  system.build.oneplus6-camera-live-power = pkgs.callPackage ./pkgs/camera/live-power.nix {
    inherit kernel;
  };
  boot.kernelModules = [ "system_heap" ];
  services.udev.extraRules = ''
    SUBSYSTEM=="dma_heap", KERNEL=="system", GROUP="video", MODE="0660", TAG+="uaccess"
  '';
  # Both processes must find the camera SPA plugin linked to our libcamera.
  # Keep the cached PipeWire/WirePlumber binaries and the tested audio plugins.
  systemd.user.services.pipewire.environment.SPA_PLUGIN_DIR = "${cameraPipewire}/lib/spa-0.2";
  systemd.user.services.wireplumber.environment.SPA_PLUGIN_DIR = "${cameraPipewire}/lib/spa-0.2";
  services.pipewire = {
    wireplumber.extraConfig."52-oneplus6-camera" = {
      "monitor.libcamera.rules" =
        map
          ({ node, description }: {
            matches = [ { "node.name" = "libcamera_input._base_soc_0_cci_ac4a000_${node}"; } ];
            actions.update-props."node.description" = description;
          })
          [
            {
              node = "i2c-bus_0_camera_1a";
              description = "后置主摄 (IMX519)";
            }
            {
              node = "i2c-bus_1_camera_10";
              description = "后置副摄 (IMX376)";
            }
            {
              node = "i2c-bus_0_camera_10";
              description = "前置摄像头 (IMX371)";
            }
          ];
    };
  };
  environment.systemPackages = [
    cameraLib
    pkgs.v4l-utils
  ];
}
