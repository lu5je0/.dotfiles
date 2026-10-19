{
  symlinkJoin,
  makeWrapper,
  baseSnapshot,
  cameraLib,
  cameraPipewire,
}:
symlinkJoin {
  name = "oneplus6-snapshot-${baseSnapshot.version}";
  inherit (baseSnapshot) version;
  paths = [ baseSnapshot ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    rm $out/bin/snapshot
    # Explicit plugin paths take precedence over the cached application's
    # GST_PLUGIN_SYSTEM_PATH_1_0. Keep its GTK/Glycin wrappers and binary.
    makeWrapper ${baseSnapshot}/bin/snapshot $out/bin/snapshot \
      --prefix GST_PLUGIN_PATH_1_0 : \
      "${cameraLib}/lib/gstreamer-1.0:${cameraPipewire}/lib/gstreamer-1.0"

    # GNOME launches this application through D-Bus, not only through PATH.
    service=$out/share/dbus-1/services/org.gnome.Snapshot.service
    cp --remove-destination \
      ${baseSnapshot}/share/dbus-1/services/org.gnome.Snapshot.service "$service"
    substituteInPlace "$service" \
      --replace-fail "${baseSnapshot}/bin/snapshot" "$out/bin/snapshot"
  '';
  meta = baseSnapshot.meta // {
    description = "GNOME Camera using the OnePlus 6 camera plugins";
    platforms = [ "aarch64-linux" ];
  };
}
