# Fn/Ctrl 桥接

- 仅用于 Lenovo 82DM、小新 Pro 13 ARE 2020、BIOS F0CN35WW。内核模块严格检查 DMI；升级固件后先重新验证 EC 协议与地址。
- EC NDS32 镜像中，命令 `0x92` 接收高、低地址字节后返回一个字节；地址小于 `0x1000` 时读取 `0x80000 + offset`。
  `0x80025` 的 bit 6 为 Fn、bit 4 为左 Ctrl；标准 ACPI EC 256 字节窗口实际对应 `0x80400–0x804FF`。
- 内核只导出 root 可读的 `/sys/kernel/fn_ctrl_ec/modifiers`，调用内核 `ec_transaction` 获取 EC 锁，拒绝休眠准备期间的读取。
  不暴露任意地址访问、写入命令、直接端口或 `/dev/mem` 访问。不能把此协议用于未经验证的固件。
- `fn-ctrl-module.service` 从 Nix 构建产物直接加载模块，避免 test/switch 时旧 modprobe 搜索树找不到新模块。
  未加载模块且运行内核与配置的内核构建不同时拒绝加载，需要重启；已存在 EC 接口时复用。
  只有一次性加载单元持有 CAP_SYS_MODULE，常驻桥接没有该权限。
- C 服务独占原始 i8042 键盘，将替代设备 `1209:f1c0` 交给 keyd；jerry 模块在 keyd 通配配置中排除原始 `0001:0001`。
  停止服务会释放虚拟键、销毁替代设备并放开物理键盘；原始键盘仍能输入，但停用整个 Nix 模块后才恢复原始设备的 keyd 规则。
- 默认空闲 100ms、Fn 按住时 10ms 检查；物理键盘事件立即触发一次读取。每次只读一个字节，复用 fd，使用阻塞 poll 和一次性 timerfd，
  没有忙等或逐键日志。空闲最多约 10 次 EC 检查/秒，Fn 配合鼠标的首次识别可能延迟约 100ms 加 EC 事务时间。
  EC 事务可能等待，不能宣称固定 10ms 延迟或未经测量的续航收益。退出日志给出 EC 等待时间、最长读取和 CPU 时间。
- 休眠期间用户进程冻结、CLOCK_MONOTONIC 定时器不计休眠时长；恢复时用 BOOTTIME 差值识别休眠并释放旧虚拟状态。
  EC 读取失败、设备丢失或 SYN_DROPPED 时退出，由 systemd 重建。启动失败不会阻止物理键盘基本输入。
- Fn+C/V 等固件合成的左 Ctrl 事件不直接转发，与 EC 中的 Fn/左 Ctrl 状态合并；右 Ctrl、Shift、Win 原样转发。
  Fn+I 实测产生 Insert，按下时还原为 I，并保存配对直到松开，避免先松 Fn 后卡键。
  Fn+PrtSc 若也产生 Insert，将无法与 Fn+I 区分；Fn+方向键、F 区、Fn+Q、背光等固件行为尚未取消，不能宣称所有键完整等价于 Ctrl。
- 构建与测试：`nix build path:.#nixosConfigurations.jerry.config.services.fn-ctrl.package --no-link`；
  内核模块：同一路径追加 `.kernelModule`。事件状态测试覆盖顺序、修饰键重叠、Insert 配对和清理；硬件行为仍需本机试用。
