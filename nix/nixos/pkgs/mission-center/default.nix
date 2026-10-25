{ mission-center }:

mission-center.overrideAttrs (old: {
  # workaround: mission-center-sidebar-order
  # 上游排序/可见性修复尚未随 1.2.0 发布；升级到包含此提交的版本后移除。
  # https://gitlab.com/mission-center-devs/mission-center/-/commit/253d2a59016c0a9b8b3114022bef95fbf7343eed
  patches = (old.patches or [ ]) ++ [ ./sidebar-order.patch ];
})
