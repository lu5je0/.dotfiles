# 一加 6

- 内核使用 `linuxPackages_7_2`，跨系列升级前验证启动、相机、Wi-Fi 和充电；不要自动回退到其他内核。
- 电量记录由 `oneplus6-battery-monitor.service` 常驻采样，日常排查优先使用已有日志。
- 修改电量记录逻辑时运行 `pkgs/battery-monitor/` 内的测试，覆盖跨日、重启追加、30 天边界和安全清理；
  清理只针对日志目录内有效日期命名的普通 CSV，不跟随符号链接。
- 设备适配和电量记录的运行细节见本目录 `README.md`。
- U-Boot 定义在 `pkgs/uboot/default.nix`，在 x86_64 Linux 宿主交叉编译生成本机 boot 镜像。
