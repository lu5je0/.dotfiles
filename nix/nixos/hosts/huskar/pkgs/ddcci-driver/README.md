# DDC/CI 背光写入确认

huskar 的 XV273K 显示器长时间息屏后，偶尔停在 GNOME 的空闲调暗值 30。
现场读数为 `brightness=89`、`actual_brightness=30`，已经解锁且 `PowerSaveMode=0`。
退出调暗和向 Mutter 重发同一个 89 都不再写硬件；改变目标后才能恢复。

上游驱动只确认 I²C 写入完成，不确认显示器是否应用亮度。这里在写入后读回
VCP 值，暂时读写失败或值不匹配时重试，最多 20 次，间隔 100 ms（另有 DDC
协议自身的等待时间）。耗尽后返回错误，不报告成功。只用于 huskar。

`test_brightness.py` 提取已打补丁的 C 函数，模拟 DDC 传输，覆盖忽略写入、暂时
读写失败、持续失败、正常写入及 blank 状态；驱动的 `checkPhase` 自动运行。

内核模块已经加载时，普通 rebuild 不会替换内存中的旧模块；重启后才使用新版本。
调试时可用 `rmmod ddcci_backlight` 仅卸载背光模块，再 `insmod` 新的 `.ko`，加载
失败需立即恢复旧模块。不要用递归卸载：`modprobe -r` 还会卸载 `ddcci` 总线，
重新创建设备时 udev 可能抢先从当前启动配置加载旧背光模块。用
`/sys/module/ddcci_backlight/srcversion` 和新 `.ko` 的 `modinfo -F srcversion` 核对。
