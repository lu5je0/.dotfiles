# OnePlus 6 / enchilada

标准 NixOS 26.05 stable + GNOME，沿用仓库根 `flake.lock`，使用 stable 的
`linuxPackages_latest`（当前 7.2.9）。不导入 Mobile NixOS。

配置入口：`nixosConfigurations.oneplus6`。复用 `profiles/base.nix` 和 GNOME 模块；
手机的共享模块参数 `pkgsUnstable` 指向 stable，未在 stable 提供的农历扩展不安装。
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

预期存储布局：

- `userdata`：现有 ext4 根分区，标签 `NIXOS_SYSTEM`，保留用户数据。
- `system_b`：FAT32 启动分区，标签 `NIXOS_BOOT`，放置内核、initrd、DTB 和 extlinux 菜单。
- Android `boot`：U-Boot 镜像。安装前保留现有启动镜像和旧 NixOS generation 用作回退。

密码哈希由手机上的 `/var/lib/nixos/secrets/oneplus6-user-password` 提供；该文件属于
root、权限 0600，不保存到仓库。SSH 仅接受 `authorized-key.pub` 中的公钥。

部署前先构建并临时启动验证 U-Boot。硬件验证尚在进行，不要仅凭配置评估成功刷写设备。
原始分区备份位于电脑 `/home/lu5je0/Projects/oneplus6-nixos/partition-backup`。
