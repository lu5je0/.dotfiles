# WeTypeX

源码使用 `github:lu5je0/fcitx5-wetypex`，提交由根目录 `flake.lock` 固定。
包定义复用上游 `nix/package.nix`，依赖使用 dotfiles 的 Nixpkgs。
原版运行时由上游包按固定 URL 和哈希从 GitHub Release 获取，未复制到 dotfiles。

所有导入 `profiles/desktop.nix` 的 NixOS 主机默认安装 WeTypeX，Fcitx5 默认输入法列表包含 WeTypeX 和英文键盘，不默认安装 Rime。
Rime 作为可选包导出为 `.#fcitx5-rime`；需要时可自行加入 Fcitx5 addons 和输入法列表。

单独安装到用户 profile：

```sh
nix profile add path:$HOME/.dotfiles#fcitx5-wetypex
```

更新上游后，desktop 主机通过重建系统更新：

```sh
cd ~/.dotfiles
nix flake update fcitx5-wetypex
sudo nixos-rebuild switch --flake .#<主机名>
```

单独安装到用户 profile 时使用 `nix profile upgrade fcitx5-wetypex` 更新。
安装或升级后重启 Fcitx5；已有个人输入法列表时，以个人设置为准，可在列表中选择 WeTypeX。
