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

## Mac

先安装 Nix，然后在 `python3 ~/.dotfiles/setup.py` 中选择 `nix-darwin`。
该模块通过根 flake 锁定的 `darwin-rebuild` 应用 `.#mac`，并在成功后清理旧的
`~/.config/nix/nix.conf -> ~/.dotfiles/nix-mac/nix.conf` 链接。

本地 flake 使用普通目录路径，让 Nix 按 Git 已跟踪文件取源，避免 `path:` 连同 `.git`
内的 socket 等运行时文件一起复制。已跟踪文件的未提交修改会生效；新增配置文件需先 `git add`。

国内二进制缓存镜像默认关闭。首次应用上面的 nix-darwin 配置后，可单独启动切源 TUI：

```sh
python3 ~/.dotfiles/nix/switch-source.py
```

该工具只支持 macOS，其他系统启动时直接拒绝；通过已安装的 fzf 显示选项。
使用方向键选择，Enter 应用，Esc 取消；当前源会排在第一项。
可选“官方 / 原有配置”与“交大 SJTUG”。选择交大时优先使用
`https://mirror.sjtu.edu.cn/nix-channels/store?priority=10`，保留已有缓存作为备用。

选择通过 sudo 保存到本机 `/etc/nix/source.conf` 并重启 Nix daemon，作用于所有用户、
root 和后台下载的默认二进制缓存。后续重建会保留选择，切源本身不需要重新构建。
重启失败会恢复原配置。切回官方会移除国内镜像追加项，恢复系统原有缓存列表。
用户配置、`NIX_CONFIG` 或命令行显式覆盖仍按 Nix 的配置优先级处理。
它只加速预编译包下载，flake inputs、GitHub 和构建时的源码下载仍使用原地址。

也可以在 Mac 的仓库根目录直接运行：

```sh
sudo -H nix --extra-experimental-features 'nix-command flakes' \
  run .#darwin-rebuild -- switch --flake .#mac
```

配置使用上游 Nix，由 nix-darwin 管理 Nix daemon 和 `/etc/nix/nix.conf`。
使用 Determinate Nix 的机器需要先处理其 Nix 管理方式，不能直接沿用这里的 `nix.settings`。

Linux 与 Mac 的 nixpkgs 输入分别跟随各自渠道，共用一份锁文件；添加 Mac 支持不会更新现有 Linux 输入。
