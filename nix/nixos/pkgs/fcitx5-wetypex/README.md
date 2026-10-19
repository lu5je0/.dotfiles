# WeTypeX

源码使用 `github:lu5je0/fcitx5-wetypex`，提交由根目录 `flake.lock` 固定。
包定义复用上游 `nix/package.nix`，依赖使用 dotfiles 的 Nixpkgs。
原版运行时由上游包按固定 URL 和哈希从 GitHub Release 获取，未复制到 dotfiles。

安装到用户 profile：

```sh
nix profile add path:$HOME/.dotfiles#fcitx5-wetypex
```

升级上游并更新已安装包：

```sh
cd ~/.dotfiles
nix flake update fcitx5-wetypex
nix profile upgrade fcitx5-wetypex
```

安装或升级后重启 Fcitx5，并在输入法列表中选择 WeTypeX。
此包不自动安装到 NixOS 系统配置，也不修改个人输入法设置。
