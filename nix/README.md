# Nix 配置

根目录的 `flake.nix` 和 `flake.lock` 同时管理 NixOS 与 Apple Silicon macOS。

- `common/packages.nix`：跨平台 CLI 清单。保留 Linux 的系统包、用户包分组；Mac 将两组一起安装。
- `common/nix.nix`：共用的 Nix 设置。
- `nixos/`：Linux 主机、模块、profiles 和 Linux 专用包。
- `darwin/default.nix`：Mac 入口；`darwin/packages.nix` 引入共用清单并追加 Mac 专属软件。

Linux 在仓库根目录选择对应主机入口，例如：

```sh
sudo nixos-rebuild switch --flake .#huskar
```

raider 使用 NixOS 静态网络管理 `ens18`，地址为 `192.168.1.3/24`，网关和 DNS 均为
`192.168.1.1`，不启用 NetworkManager。实际主机名尚未与配置一致时，显式指定入口：

```sh
nh os switch --hostname raider
```

应用网络配置可能中断 SSH；需要时通过虚拟机控制台操作，随后连接 `192.168.1.3`。

## 桌面应用图标

桌面 profile 引入 `nixos/modules/desktop-icons`，在
`nixos/profiles/desktop.nix` 配置启动项 ID 与图标文件即可，支持 SVG、PNG 等桌面图标格式：

```nix
programs.desktopIconOverrides = {
  "io.github.yucling.open-orpheus" = ../modules/desktop-icons/icons/netease-cloud-music.svg;
  "org.gnome.Nautilus" = ./icons/files.png;
};
```

内置图标放在 `nixos/modules/desktop-icons/icons/`。
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

## GNOME 的 Nix 应用自动刷新

GNOME 模块安装 `nix-profile-applications.path` 和同名用户服务。通过 inotify 监视用户
profile 的父目录、系统 profile 和 `/run/current-system` 切换；登录时也同步一次，不使用轮询或定时器。
支持 `nix profile add/upgrade/remove`、`nh os switch` 和系统中的用户包，用户 profile 优先。

服务在 `~/.local/share/applications`（或 `$XDG_DATA_HOME/applications`）生成启动项，
把 profile 提供的图标名改为实际图标文件的绝对路径，绕开 GNOME 的图标主题缓存。
保留启动命令、动作及文件关联；profile 没提供的图标继续按主题名查找。此服务不处理托盘图标。
绝对路径固定图标选择，不随图标主题切换。
同步及图标覆盖服务都会刷新用户目录的 `mimeinfo.cache`，使用户启动项覆盖系统入口后仍能参与
文件类型关联；不修改用户的默认应用偏好。

状态记录在 `$XDG_STATE_HOME/nix-profile-applications`（默认 `~/.local/state/` 下）。
升级时刷新、卸载时清理，只修改本服务生成且未被用户编辑的文件；已有手工启动项及其他来源的链接
不会被覆盖。直接指向 profile 启动项的链接会被接管。`programs.desktopIconOverrides` 中配置的
启动项交给图标覆盖服务处理，profile 切换后也会触发该服务刷新。

查看监视状态和同步日志：

```sh
systemctl --user status nix-profile-applications.path
journalctl --user -u nix-profile-applications.service -n 30
```

手动触发一次检查：

```sh
systemctl --user restart nix-profile-applications.service
```

世代未变时服务直接退出。需要强制重建时，在 `systemctl --user cat nix-profile-applications.service`
显示的 `ExecStart` 命令后加 `--force`，保留其中的 `--exclude` 参数。
不要删除状态清单：它用于区分自动生成的启动项和用户文件。

测试：`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s nix/tests -p 'test*desktop*.py'`
以及 `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s nix/tests -p 'test_profile_applications.py'`。
MIME 集成测试需要 `gio` 和 `update-desktop-database`；后者也可用 `UPDATE_DESKTOP_DATABASE` 指定绝对路径。

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

## 局域网构建缓存

huskar 在 `192.168.1.100:17500` 运行 `nix-serve`，提供本机仍保留在 Nix store 中的构建结果。
该地址需要在路由器上保留，服务仅监听此 IPv4 地址。其他 NixOS 主机通过 base profile
信任缓存地址及签名公钥，但不将其加入默认下载源；huskar 自身不使用该缓存，macOS 不添加此 Linux 缓存。
缓存不会代替客户端构建缺失的包，GC 清理的 store 路径也不再可用。

客户端照常执行 `nh os switch` 或 `nh os build`。nh 包装脚本先用最多 1 秒访问缓存接口，
成功才通过本次进程的 `NIX_CONFIG` 追加缓存；不可用时继续使用原有缓存。
其他 nh 子命令和直接执行的 Nix 命令不启用该缓存。此探测只判断启动时的可用性，
不保证下载过程中断网时立即回退。

签名私钥位于 huskar 的 `/var/lib/nix-cache/cache-private-key.pem`，不进入 Git 或 Nix store。
首次部署时，将本机生成的私钥安装到服务读取的位置，再应用配置：

```sh
sudo install -d -m 700 /var/lib/nix-cache
sudo install -o root -g root -m 600 \
  ~/.local/state/nix-cache/cache-private-key.pem \
  /var/lib/nix-cache/cache-private-key.pem
sudo nixos-rebuild switch --flake ~/.dotfiles#huskar
curl --fail http://192.168.1.100:17500/nix-cache-info
```

保管好与 base profile 中公钥对应的私钥；重装时恢复同一密钥。
更换密钥时需要同步更新客户端的 `trusted-public-keys`。

其他 NixOS 主机首次切换也要使用缓存时，先确保 huskar 的缓存服务已启动，
再临时传入缓存地址和公钥，不依赖尚未生效的客户端配置：

```sh
cd ~/.dotfiles
git pull --ff-only

sudo nixos-rebuild switch --flake ".#$(hostname)" \
  --option extra-substituters 'http://192.168.1.100:17500?priority=30' \
  --option extra-trusted-public-keys \
  'huskar-1:/hAtuYEwzeOuSwvlOQGbWT4omIu18D1u64jg33LdXyg='
```

主机名须与 flake 中的配置名称一致，例如 `jerry`、`raider` 或 `oneplus6`。
此命令优先尝试 huskar，未命中的包仍使用原有缓存；切换后继续使用
`nh os switch` / `nh os build`，由包装脚本自动探测缓存。

其他 NixOS 主机应用各自配置后生效；复用二进制要求对应的 store 路径完全一致，
通常需要相同平台、锁定输入和包构建参数。

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
