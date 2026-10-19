# Nix 配置

根目录的 `flake.nix` 和 `flake.lock` 同时管理 NixOS 与 Apple Silicon macOS。

- `common/packages.nix`：跨平台 CLI 清单。保留 Linux 的系统包、用户包分组；Mac 将两组一起安装。
- `common/nix.nix`：共用的 Nix 设置。
- `nixos/`：Linux 主机、模块、profiles 和 Linux 专用包。
- `darwin/default.nix`：Mac 入口；`darwin/packages.nix` 引入共用清单并追加 Mac 专属软件。

Linux 的主机入口名称不变，例如在仓库根目录运行：

```sh
sudo nixos-rebuild switch --flake path:.#huskar
```

## Mac

先安装 Nix，然后在 `python3 ~/.dotfiles/setup.py` 中选择 `nix-darwin`。
该模块通过根 flake 锁定的 `darwin-rebuild` 应用 `.#mac`，并在成功后清理旧的
`~/.config/nix/nix.conf -> ~/.dotfiles/nix-mac/nix.conf` 链接。

也可以在 Mac 的仓库根目录直接运行：

```sh
sudo nix --extra-experimental-features 'nix-command flakes' \
  run path:.#darwin-rebuild -- switch --flake path:.#mac
```

配置使用上游 Nix，由 nix-darwin 管理 Nix daemon 和 `/etc/nix/nix.conf`。
使用 Determinate Nix 的机器需要先处理其 Nix 管理方式，不能直接沿用这里的 `nix.settings`。

Linux 与 Mac 的 nixpkgs 输入分别跟随各自渠道，共用一份锁文件；添加 Mac 支持不会更新现有 Linux 输入。
