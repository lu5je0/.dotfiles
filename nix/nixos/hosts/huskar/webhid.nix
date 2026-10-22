{ pkgs, ... }:

{
  # WebHID 需要读写 hidraw；在 73-seat-late.rules 前标记，由 logind 授权给当前本地会话。
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "webhid-peripherals-udev-rules";
      destination = "/lib/udev/rules.d/70-webhid-peripherals.rules";
      text = ''
        # ATK 鼠标 8K 接收器（373b:11d9）
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="373b", ATTRS{idProduct}=="11d9", TAG+="uaccess"

        # PMO 键盘 2.4G 接收器（36b0:3002）
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="36b0", ATTRS{idProduct}=="3002", TAG+="uaccess"
      '';
    })
  ];
}
