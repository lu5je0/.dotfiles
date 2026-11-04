{ btop }:

btop.overrideAttrs (oldAttrs: {
  # btop 1.4.8 的 AMD sysfs 后端在显卡休眠、功耗读取失败时可能留下空采样队列。
  # CPU 面板和独立 GPU 面板绘制时均以 0 兜底，避免对空 deque 调用 back()，保留 GPU 监控。
  # 上游包含此修复后可移除补丁：https://github.com/aristocratos/btop/pull/1939
  patches = (oldAttrs.patches or [ ]) ++ [ ./gpu-empty-deque.patch ];
})
