# Fcitx5 Rime

独立的 Rime 插件包，包含雾凇拼音的方案、词库、Lua、OpenCC 数据，
以及 `ime/rime/` 中的 Linux 个人配置和 `ime/themes/` 的微信主题。
Fcitx5、librime（含 Lua 插件）与雾凇拼音均由根 flake 锁定的 Nixpkgs 提供，
构建时自动获取依赖，无需安装脚本或在用户目录克隆仓库。

安装到用户 profile：

```sh
nix profile add path:$HOME/.dotfiles#fcitx5-rime
```

安装后重新登录，让会话的 `XDG_DATA_DIRS` 包含用户 profile 的 `share`，
再在 Fcitx5 配置中添加「中州韵」。插件描述使用 Nix store 中的绝对库路径，
可以由现有系统 Fcitx5 加载；系统的默认输入法仍由 `modules/fcitx5.nix` 管理。

也可以在 NixOS 配置中加入：

```nix
i18n.inputMethod.fcitx5.addons = [
  (pkgs.callPackage ../pkgs/fcitx5-rime { })
];
```

包内共享数据位于 `share/rime-data`；个人配置修改后重新构建或升级 profile。
在 `python3 ~/.dotfiles/setup.py` 中选择 `fcitx5`，将 `ime/fcitx5/` 整目录链接为
`~/.config/fcitx5`。Fcitx5 设置界面的修改仍写回 dotfiles；
改这部分无需重建 Rime 包。`ime/rime/` 的配置则在修改后运行
`nix profile upgrade fcitx5-rime`，再执行「重新部署」。
用户词频、学习数据和部署产物继续写入 `~/.local/share/fcitx5/rime`。
该目录内同名的旧方案、词库链接和配置会优先于包内文件；使用过旧脚本时，
先备份，再移走需要改由 Nix 管理的同名文件，保留用户词库、学习数据。
然后在 Fcitx5 中执行「重新部署」。

候选框主题可在 Fcitx5 外观设置中选择 `wechat` 或 `wechat-dark`。
`ime/fcitx5/`、会话环境变量、自动启动、fontconfig 和 KWin 设置属于用户或系统配置，
不由插件包写入；NixOS 的 Fcitx5 模块负责框架与会话集成。
macOS 的 Squirrel 配置保留在 `ime/rime/squirrel.custom.yaml`，本包仅支持 Linux。

更新依赖时更新根 flake 的 Nixpkgs，再执行 `nix profile upgrade fcitx5-rime`。
