# Nix 配置

## 包组织

- 主机专用包放在 `nixos/hosts/<主机名>/pkgs/<包名>/`，共用包放在 `nixos/pkgs/`。
- 需要独立构建入口时，可由根 flake 引用主机包目录，包定义仍留在所属主机下。
- Linux / Darwin 共用的本地包也统一放 `nixos/pkgs/<包名>/`，跨平台软件清单 `common/packages.nix` 可直接引用；目录位置不限制构建平台。
- `nixos/pkgs/default.nix` 登记 Linux 共用包的独立构建 / profile 安装入口，接收 `{ pkgs, pkgsUnstable, inputs }` 并返回单平台包集合。
- 包表达式用 `default.nix`；补丁、图标、升级脚本放同目录。
- 单包能通过 wrapper、补丁等解决的问题留在包内，系统级配置才放进对应平台目录。
- 包需要外部 flake 时，在根 `flake.nix` 登记 input，通过 `callPackage` 参数传入，包目录不自带 flake。

## 配置归属

- NixOS 与 Darwin 各自维护安装和导出入口，根 flake 提供独立构建入口；按实际复用需求组织共用定义。
- Darwin 通过 `common/packages.nix` 及自身清单安装软件，可用自己的 `pkgs.callPackage` 直接引用共用包定义，不导入 Linux 个人包导出清单。
- 跨平台软件清单放 `common/packages.nix`，由 `nixos/modules/packages.nix` 和 `darwin/packages.nix` 引入，
  平台专属软件在各自清单中追加。共用 Nix 设置放 `common/nix.nix`。
- Linux 额外缓存优先配置在 `nixos/profiles/base.nix`。
- 不进系统配置的包安装到用户 profile。
