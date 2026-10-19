{ pkgs, ... }:

let
  mountOptions = [
    "username=admin"
    "password=lu5je0"
    "uid=lu5je0"
    "gid=users"
    "vers=3.1.1"
    "_netdev"
    "soft"
    "noatime"
    "nofail"
    "noauto"
    # 共享根被服务端映射成 0555，客户端权限检查会把写入拦成 EACCES；
    # 关掉客户端检查，交给服务端 ACL 判定（uid/gid 已强制成当前用户）
    "noperm"
    "x-systemd.automount"
    "x-systemd.idle-timeout=600"
    "x-systemd.mount-timeout=15"
  ];
in
{
  environment.systemPackages = [ pkgs.cifs-utils ];
  boot.supportedFilesystems = [ "cifs" ];

  fileSystems."/mnt/st2000" = {
    device = "//192.168.1.10/st2000";
    fsType = "cifs";
    options = mountOptions;
  };

  fileSystems."/mnt/mg08" = {
    device = "//192.168.1.10/mg08";
    fsType = "cifs";
    options = mountOptions;
  };

  fileSystems."/mnt/share" = {
    device = "//192.168.1.10/share";
    fsType = "cifs";
    options = mountOptions;
  };

  systemd.tmpfiles.rules = [
    "d /mnt/st2000 0555 root root -"
    "d /mnt/mg08 0555 root root -"
    "d /mnt/share 0555 root root -"
  ];
}
