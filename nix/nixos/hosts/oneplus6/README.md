# OnePlus 6 / enchilada

标准 NixOS 26.05 stable + GNOME，沿用仓库根 `flake.lock`，使用 stable 的
`linuxPackages_7_2`（当前 7.2.9）。不导入 Mobile NixOS。
内核固定在已验证的 7.2 系列，更新 `flake.lock` 时可以获取该系列的补丁版本，
不会自动跳到下一系列。跨系列升级需手动修改 `hardware-configuration.nix`，
并验证启动、相机、Wi-Fi 与充电模块；若 nixpkgs 移除了 7.2 系列，求值会报错，
不会回退到其他内核。

配置入口：`nixosConfigurations.oneplus6`。复用 `profiles/base.nix` 和 GNOME 模块；
手机的共享模块参数 `pkgsUnstable` 指向 `aarch64-linux` 的 unstable 包集，
用于 Neovim、Python、pi-coding-agent 和农历扩展；系统、GNOME 和内核仍来自 stable。
手机桌面设置集中在 `profiles/phone.nix`，硬件设置集中在本目录。

```sh
nix build .#oneplus6-uboot
sudo nixos-rebuild build --flake .#oneplus6
```

U-Boot 是一加 6 的启动适配，加载标准 NixOS 的内核、initrd 和 extlinux 配置。
主机专用包放在本目录的 `pkgs/`；U-Boot 包定义位于 `pkgs/uboot`，对应源码固定到 Tauchgang 提交
`1f56592576887ffcae0e7d44c66b5cf030674908`。
包内 `extlinux.patch` 将默认 EFI 启动改为按分区名查找 `system_b`，读取
`/extlinux/extlinux.conf`；保留音量键启动菜单和 USB 调试入口，无需修改 GPT 类型。
固件包定义参考 vanilla-mobile-nixos 提交
`2a67cae0d5102f97cb810e29b3989b42847c6765`；此仓库仅使用独立固件包，未导入其系统框架。

已安装的存储布局：

- `userdata`：现有 ext4 根分区，标签 `NIXOS_SYSTEM`，保留用户数据。
- `system_b`：FAT32 启动分区，标签 `NIXOS_BOOT`，放置内核、initrd、DTB 和 extlinux 菜单。
- Android `boot_a`：U-Boot 镜像，A 槽已标记启动成功。
- Android `boot_b`：固定到旧 Mobile NixOS generation 的回退镜像；旧系统另有 GC root 保留。

手机的 `/etc/nixos` 指向 `/home/lu5je0/.dotfiles`。正常更新在手机执行：

```sh
cd ~/.dotfiles
sudo nixos-rebuild switch --flake path:.#oneplus6
```

日常更新内核通过 extlinux 完成，不需要重新刷写 Android boot 分区。
电脑开发副本位于 `/home/lu5je0/Projects/dotfiles`，已合并到 `master`。

启动适配在 `hardware-configuration.nix` 和 `pkgs/device-tree/`：提前加载 LMh、OSM、
显示参考电源、USB PHY 与 RTC，保留 Android 固件已配置的 SW_CTRL 引脚。
Docker 按需启动。实测普通重启到图形目标约 16 秒。

`qualcomm.nix` 提供标准 nixpkgs 的 rmtfs、tqftpserv；调制解调器 NV 分区只读访问。
`pkgs/ath10k-wcn3990/` 将此设备的 VHT 信道宽度限制为 80 MHz：7.2.9 原驱动连接
160 MHz AP 时认证帧收不到 ACK，限制后 5 GHz 能正常认证和联网。
只重建 ath10k_core、ath10k_snoc 两个模块，完整内核继续使用 stable 的二进制缓存。
同包回移了 [WCN3990 PMF peer flag 修复](https://lkml.iu.edu/2610.1/19751.html)：
固件支持 PMF，却未在 firmware-5.bin 声明对应 feature，原驱动因此漏发 peer PMF 标志。
本机保留 PMF 时，修复前到路由器平均延迟约 28 ms、周期性跳到 100 ms 以上；
修复后 300 次 ping 平均 2.34 ms、最大 6.11 ms，零丢包，PMF 保持开启。
`usb-network.nix` 自动加载 USB Ethernet gadget，手机固定地址 `169.254.42.1/16`，
电脑使用同网段 link-local 地址后可 SSH 管理。SSH 用户为 `lu5je0`。

蓝牙需要本机的 `qca/crbtfw21.tlv`，不能使用通用 linux-firmware 中的同名文件。
`pkgs/firmware/` 的优先级设为 5（数字越小优先级越高），覆盖优先级为 6 的
linux-firmware；反过来会在固件下载后报 `Opcode 0x0c03 failed: -110`。
设备 NVM 还包含占位地址，`bluetooth.nix` 在 BlueZ 启动前运行
`pkgs/bluetooth-address/`：仅对缺少 public-address 的 WCN3990 控制器，
根据本机 `/etc/machine-id` 派生固定的本地单播地址，并通过 BlueZ 管理接口配置。
已有有效地址时保持原样；不需要重编内核或写入厂商分区。
已验证控制器开启、BR/EDR 与 LE 支持，以及扫描附近设备；实际配对与蓝牙音频仍需设备验证。

`audio.nix` 为 PipeWire 和 WirePlumber 指定本机的 ALSA UCM 路由，包位于
`pkgs/alsa-ucm/`，固定到 sdm845-mainline 提交 `628b9900cdd2b9b8356201293f1da5396cf0ca27`。
该配置提供扬声器、3.5 mm 耳机及麦克风；去掉标准内核没有的 Q6Voice 通话控制项，
避免只有虚拟输出或启用 HiFi 失败。通话音频未适配。
WirePlumber 固定本机音频为 48 kHz/S16LE：同为 80% 音量时，S24_LE 无声，
S16_LE 能正常播放。内置声卡默认输出音量为 80%，已有的用户音量设置仍优先。

`camera.nix` 提供本机的摄像头栈：`pkgs/camera/` 从 SDM845 维护者提交
`85f1df2a4ec71d7a91dd95a7a49f889d1595ffa8` 构建 IMX519 主摄、IMX376K 后置副摄、
IMX371 前摄和 LC898217XC 对焦模块，并为 stock CAMSS 模块回移 C-PHY 补丁。
完整 7.2.9 内核保持不变；`pkgs/device-tree/camera.dts` 补上供电、复位、时钟和 CSI 连接，
与原有 Wi-Fi 引脚修复一起合入启动 DTB。

`pkgs/libcamera/` 使用官方 0.7.2、postmarketOS 的 IMX371 Quad Bayer 补丁及传感器调参，
补齐三颗 Sony 传感器的增益换算，并启用 Adreno 630 GPU 软件 ISP。包目录 pkgs/pipewire-camera/
只重建链接本机 libcamera 的相机 SPA 插件，通过 SPA_PLUGIN_DIR 提供给 PipeWire 和 WirePlumber，
复用缓存中的音频主体及其他插件。包目录 pkgs/snapshot/ 复用缓存中的 GNOME Camera 二进制，优先加载本机的
相机插件，并修正 D-Bus 启动入口。界面中区分 IMX519 主摄、IMX376 副摄和 IMX371 前摄。
不更改其他主机的相机包。调参使用社区的通用色彩矩阵，
不包含 Android 厂商的计算摄影、HDR、电子防抖或画质算法。
实景仍有轻微偏绿，尚未完成针对本机的精确色彩及镜头校准。
三个传感器均已通过 RAW 和 640×480 彩色连续取帧验证，主摄另通过 1280×720 处理输出测试。
IMX519 的实验性缩小模式存在不出帧或画面不完整问题，目前只公开稳定的 4656×3496 模式，
由 GPU 缩放预览；实测约 11 fps，不能视作 Android 相机的帧率或画质。GNOME 相机的自动对焦、录像尚未验证。
`pkgs/libcamera/gpu-stats-window.patch` 修正普通 Bayer 的 GPU 测光窗口：预览由整幅原图缩放，
统计也应覆盖原图，不能把 640×480 的预览尺寸当作原图左上角的测光区域。
手机 `~/Projects/op6-monitor` 的 Docker 网页监控另有 `focus.py`，使用已有 LC898217XC
驱动按需进行后摄对比度搜索；不代表 simple pipeline 已支持 libcamera 的通用 AF 控制。
主摄增加电源及 PLL 稳定等待，已通过自动断电后的 16 次交替启动测试。
IMX376 的 2592×1940 模式使用本机 RAW 测得的相位像素位置，在 GPU 去马赛克及 CPU
白平衡统计中插值校正；原始 RAW 输出保持不变。全画幅、边界及四种翻转组合的回归测试随包构建运行。
本次通过热加载完成硬件验证；修改后的静态 DTB 和模块组合尚未经过整机重启验证。

```sh
cam --list
media-ctl --print-topology
# 先关闭占用摄像头的应用；三个镜头共用 CAMSS 管线。
__EGL_VENDOR_LIBRARY_DIRS=/run/opengl-driver/share/glvnd/egl_vendor.d \
  python3 nix/nixos/hosts/oneplus6/scripts/camera-smoke-test.py \
  --directory "$HOME/.cache/oneplus6-camera-test-$(date +%Y%m%d-%H%M%S)"
```

`system.build.oneplus6-camera` 和 `system.build.oneplus6-libcamera` 可单独构建诊断组件。
相机包中的 overlay helper 仅供当前开机周期的手动调试，不自动加载；正常开机使用静态 DTB。
`oneplus6-camera-live-power` 仅在无需重启的调试中为新增的 LVS1 注册独立相机供电实例，
避免重新绑定整机 PMIC。不要在相机正在使用时卸载这些临时 overlay；重启后由静态配置接管。

`power.nix` 和 `pkgs/power-key/` 将物理电源键短按改为仅熄屏、再次点亮，不触发锁屏。
本机默认关闭 GNOME 自动锁屏，避免熄屏后因空闲计时要求密码；仍可从桌面菜单手动锁屏。
通过 GNOME 原生屏保接口协调显示状态，避免直接关闭未锁屏桌面的面板导致 Mutter 崩溃。
手动锁屏后，电源键仅唤醒屏幕，仍需正常解锁。
GDM 登录界面仅切换面板电源，不调用屏保激活或退出接口，避免把登录窗口移出屏幕。
切换时等待 GNOME 动画完成，忽略期间及完成后 350 ms 内积压的连按事件；
唤醒时显式恢复面板电源，避免屏保已退出但屏幕仍黑。动画超时也会尝试恢复亮屏。
电源键熄屏前临时独占 Synaptics 触屏输入，阻止触摸将 GNOME 唤醒；再次按电源键亮屏后释放触屏。
按设备名称查找触屏，不依赖 event 编号；失败时恢复亮屏和触屏，服务退出也会自动释放独占。
7.2.9 的 s2idle 休眠在此设备上无法恢复，因此禁用整机休眠和自动休眠；
屏幕熄灭时系统仍运行，耗电会高于正常休眠。

`charging.nix` 默认开机启动 `oneplus6-bypass.service`，每 15 秒检查一次电量：
低于 40% 恢复充电，高于 60% 暂停充电，40%～60%（含端点）保持当前模式，避免反复切换。
启动时处于区间内也保留当前硬件模式；驱动初始化默认正常充电。USB 输入始终保留。
`pkgs/charge-control/` 提供控制程序；电量读取失败、停止服务或退出时恢复正常充电。
`pkgs/pmi8998-charger/` 只重建 `qcom_smbx` 模块，增加标准
`/sys/class/power_supply/pmi8998-charger/charge_behaviour` 接口。该补丁参考
`~/junk-file/2026/10/2026-10-17T204353-一加6旁路充电.diff` 中的充电使能位，
适配 7.2.9 并补齐参数校验、错误返回、状态通知及卸载恢复。

```sh
sudo systemctl stop oneplus6-bypass   # 恢复正常充电
sudo systemctl start oneplus6-bypass  # 启动 40%～60% 自动控制
cat /sys/class/power_supply/pmi8998-charger/charge_behaviour
```

阈值由 `hardware.oneplus6-charging.lowerThreshold` 和 `upperThreshold` 配置。
设置 `hardware.oneplus6-charging.bypassOnBoot = false;` 可改为开机正常充电、手动启动自动控制。
停止服务、启动失败或驱动卸载会恢复正常充电。这里是充电抑制，不是物理断开电池；
外部供电不足时电池仍会补电。电脑 USB 限流 500 mA 时，负载较高会出现电池放电；
换用识别为 DCP 的充电器后，输入限流为 1.5 A，正常充电时电池电流约 1.04 A，
空闲暂停充电的 25 秒测试中电池电流持续读到 0 mA。短测不代表长期或高负载下始终零放电。

`battery-monitor.nix` 将 `oneplus6-battery-monitor.service` 配置为开机常驻服务，
异常退出自动重启，无截止时间。程序和测试位于 `pkgs/battery-monitor/`，
每 60 秒只读记录一次电量、电流、电压、温度、充电状态及系统负载，不改变充电策略。
电流单位为 µA（正为充电、负为放电），电压为 µV，温度为 0.1°C；
电量百分比及满充容量可能被电量计重新估算，不能把百分比突变直接换算成耗电。

数据存放在 `/var/lib/oneplus6-battery-monitor/YYYY-MM-DD.csv`，按本机时区分日追加，
重启后接着写，不覆盖已有数据。启动及日期变化时自动清理，只保留包含当天在内最近
30 个自然日；正常每分钟采样时每天约 1440 条记录，磁盘占用不会随运行年限持续增长。
按现有记录平均约 139 字节/条估算，30 天 CSV 合计约 6 MB（5.7 MiB），实际随字段长度略有变化。
服务以独立系统用户运行，目录权限为 0755、CSV 为 0644；普通用户无需 `sudo`
即可读取，写入仅允许服务用户。

```sh
systemctl status oneplus6-battery-monitor
journalctl -u oneplus6-battery-monitor -n 20
tail /var/lib/oneplus6-battery-monitor/$(date +%F).csv
ls -lh /var/lib/oneplus6-battery-monitor/
```

原先的 24 小时临时记录在部署常驻服务时迁入对应日期的 CSV，旧临时服务停止，
之后只保留这一套采样。维护约定见本目录 `AGENTS.md`。

密码哈希由手机上的 `/var/lib/nixos/secrets/oneplus6-user-password` 提供；该文件属于
root、权限 0600，不保存到仓库。SSH 支持该用户的密码登录和
`authorized-key.pub` 中的公钥登录，禁止 root 直接登录。

已验证触屏 GNOME、屏幕键盘、2.4/5 GHz Wi-Fi、USB/Wi-Fi SSH、熄屏点亮、普通重启，
以及蓝牙开启、扫描、配对与图片发送。蓝牙音频和蜂窝通信尚未验证；相机验证范围见上文。
原始分区备份位于电脑 `/home/lu5je0/Projects/oneplus6-nixos/partition-backup`。
