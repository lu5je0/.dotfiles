# OnePlus 6 / enchilada

标准 NixOS 26.05 stable + GNOME，沿用仓库根 `flake.lock`，使用 stable 的
`linuxPackages_latest`（当前 7.2.9）。不导入 Mobile NixOS。

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

`power.nix` 和 `pkgs/power-key/` 将物理电源键短按改为锁屏熄屏、再次点亮。
7.2.9 的 s2idle 休眠在此设备上无法恢复，因此禁用整机休眠和自动休眠；
屏幕熄灭时系统仍运行，耗电会高于正常休眠。

密码哈希由手机上的 `/var/lib/nixos/secrets/oneplus6-user-password` 提供；该文件属于
root、权限 0600，不保存到仓库。SSH 仅接受 `authorized-key.pub` 中的公钥。

已验证触屏 GNOME、屏幕键盘、2.4/5 GHz Wi-Fi、USB/Wi-Fi SSH、熄屏点亮和普通重启。
蓝牙、相机和蜂窝通信尚未验证。
原始分区备份位于电脑 `/home/lu5je0/Projects/oneplus6-nixos/partition-backup`。
