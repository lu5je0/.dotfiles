# Nix 配置

根目录的 `flake.nix` 和 `flake.lock` 同时管理 NixOS 与 Apple Silicon macOS。

- `common/packages.nix`：跨平台 CLI 清单。保留 Linux 的系统包、用户包分组；Mac 将两组一起安装。
- `common/nix.nix`：共用的 Nix 设置。
- `nixos/`：Linux 主机、模块、profiles 和 Linux 专用包。
- `darwin/default.nix`：Mac 入口；`darwin/packages.nix` 引入共用清单并追加 Mac 专属软件。

Linux 的主机入口名称不变，例如在仓库根目录运行：

```sh
sudo nixos-rebuild switch --flake .#huskar
```

## 桌面应用图标

桌面 profile 引入 `nixos/modules/desktop-icons.nix`，在
`nixos/profiles/desktop.nix` 配置启动项 ID 与图标文件即可，支持 SVG、PNG 等桌面图标格式：

```nix
programs.desktopIconOverrides = {
  "io.github.yucling.open-orpheus" = ./icons/netease-cloud-music.svg;
  "org.gnome.Nautilus" = ./icons/files.png;
};
```

ID 是 `.desktop` 文件名，可省略后缀，不是窗口标题或可执行文件名。图片路径相对于
配置所在的 Nix 文件；新增本地图片要先加入 Git，flake 才能读取。

模块在图形会话启动时按 `XDG_DATA_DIRS` 的优先级查找原启动项，在用户的
`XDG_DATA_HOME/applications`（默认 `~/.local/share/applications`）生成同名覆盖，
只修改主图标，保留启动命令、文件关联和右键动作，适用于 Flatpak 和普通桌面应用。
移除配置后会清理模块生成的覆盖；尚未安装的应用会跳过。已有手工创建的同名用户启动项
不会被覆盖，冲突详情见 `journalctl --user -u desktop-icon-overrides`。

rebuild 后可手动刷新当前会话；应用升级或安装后也可运行：

```sh
systemctl --user restart desktop-icon-overrides.service
```

完全退出应用后重新打开；Dock 仍显示缓存图标时注销再登录。

## Mac

先安装 Nix，然后在 `python3 ~/.dotfiles/setup.py` 中选择 `nix-darwin`。
该模块通过根 flake 锁定的 `darwin-rebuild` 应用 `.#mac`，并在成功后清理旧的
`~/.config/nix/nix.conf -> ~/.dotfiles/nix-mac/nix.conf` 链接。

本地 flake 使用普通目录路径，让 Nix 按 Git 已跟踪文件取源，避免 `path:` 连同 `.git`
内的 socket 等运行时文件一起复制。已跟踪文件的未提交修改会生效；新增配置文件需先 `git add`。

也可以在 Mac 的仓库根目录直接运行：

```sh
sudo -H nix --extra-experimental-features 'nix-command flakes' \
  run .#darwin-rebuild -- switch --flake .#mac
```

配置使用上游 Nix，由 nix-darwin 管理 Nix daemon 和 `/etc/nix/nix.conf`。
使用 Determinate Nix 的机器需要先处理其 Nix 管理方式，不能直接沿用这里的 `nix.settings`。

Linux 与 Mac 的 nixpkgs 输入分别跟随各自渠道，共用一份锁文件；添加 Mac 支持不会更新现有 Linux 输入。

## 全局切源

国内二进制缓存镜像默认关闭。首次应用本仓库的 NixOS / nix-darwin 配置后，可单独启动切源 TUI：

```sh
python3 ~/.dotfiles/nix/switch-source.py
```

支持 macOS 与使用 systemd 的 Linux，多用户 Nix daemon 需已安装；其他环境启动时直接拒绝。
普通 Linux 的多用户 Nix 安装可手动在系统 `nix.conf` 末尾接入 `!include /etc/nix/source.conf`。
通过已安装的 fzf 显示选项，使用方向键选择、Enter 应用、Esc 取消；当前源会排在第一项。
可选“官方 / 原有配置”与“交大 SJTUG”。选择交大时优先使用
`https://mirror.sjtu.edu.cn/nix-channels/store?priority=10`，保留已有缓存作为备用。

选择通过 sudo 保存到本机 `/etc/nix/source.conf`。Mac 通过 launchd 重启 Nix daemon，
Linux 通过 `systemctl restart nix-daemon.service` 重启，作用于所有用户、root 和后台下载的默认二进制缓存。
切源本身不需要重新构建；重启失败会恢复原配置。

本机的 `source.conf` 不由 NixOS / nix-darwin 生成，rebuild 只重新生成带
`!include /etc/nix/source.conf` 的 `nix.conf`，因此会保留选择，各机器互不影响。
切回官方会移除国内镜像追加项，恢复系统原有缓存列表。
用户配置、`NIX_CONFIG` 或命令行显式覆盖仍按 Nix 的配置优先级处理。
它只加速预编译包下载，flake inputs、GitHub 和构建时的源码下载仍使用原地址。
