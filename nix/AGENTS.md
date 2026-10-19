# Nix 配置

## 包组织

- NixOS 主机专用包放 `nixos/hosts/<主机名>/pkgs/<包名>/`，由主机配置就近引用；多台 Linux 主机共用后
  才移入 `nixos/pkgs/<包名>/`，并在 `nixos/pkgs/default.nix` 登记。
- 主机专用包需要导出 flake 构建入口时，根 flake 直接引用主机目录，不为导出而搬进共用目录。
- 包表达式用 `default.nix`；补丁、图标、升级脚本放同目录。
- 单包能通过 wrapper、补丁等解决的问题留在包内，系统级配置才放进对应平台目录。
- 包需要外部 flake 时，在根 `flake.nix` 登记 input，通过 `callPackage` 参数传入，包目录不自带 flake。

## 配置归属

- 跨平台软件清单放 `common/packages.nix`，由 `nixos/modules/packages.nix` 和 `darwin/packages.nix` 引入，
  平台专属软件在各自清单中追加。共用 Nix 设置放 `common/nix.nix`。
- Linux 额外缓存优先配置在 `nixos/profiles/base.nix`。
- 不进系统配置的包安装到用户 profile。
