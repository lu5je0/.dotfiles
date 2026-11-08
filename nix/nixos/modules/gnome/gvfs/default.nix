{ pkgs, ... }:

{
  # 批量删除时按路径索引待发通知，避免元数据服务反复扫描整个队列。
  # 上游问题见 https://gitlab.gnome.org/GNOME/gvfs/-/work_items/885
  services.gvfs.package = pkgs.gvfs.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [ ./metadata-notification-index.patch ];
  });
}
