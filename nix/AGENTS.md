# Nix 配置

## 包组织

- **主机专用包必须内聚到 `nixos/hosts/<主机名>/pkgs/<包名>/`，不得在通用 `nixos/pkgs/` 下存放定义，也不得在 `nixos/pkgs/default.nix` 中登记或引用。** 只有实际被多台主机共用后，才移入通用包目录。
- 主机专用包默认不向根 flake 导出快捷入口。只有用户明确要求独立的 `nix build .#<包名>` 入口时，才由根 flake 直接引用主机包目录；不为导出搬动包定义，也不新增汇总文件或自动发现机制。
- Linux / Darwin 共用的本地包也统一放 `nixos/pkgs/<包名>/`，跨平台软件清单 `common/packages.nix` 可直接引用；目录位置不限制构建平台。
- `nixos/pkgs/default.nix` 只登记 Linux 个人包的独立构建 / profile 安装入口，接收 `{ pkgs, pkgsUnstable, inputs }` 并返回单平台包集合；不维护 Darwin 导出、逐包平台标记或跨平台筛选。此清单不登记主机专用包。
- 包表达式用 `default.nix`；补丁、图标、升级脚本放同目录。
- 单包能通过 wrapper、补丁等解决的问题留在包内，系统级配置才放进对应平台目录。
- 包需要外部 flake 时，在根 `flake.nix` 登记 input，通过 `callPackage` 参数传入，包目录不自带 flake。

## 配置归属

- NixOS 与 Darwin 各自维护安装和导出入口；根 flake 只保留实际使用的独立构建入口，不为共用软件安装扩展整套跨平台包导出。不增加汇总文件或自动扫描包目录。
- Darwin 通过 `common/packages.nix` 及自身清单安装软件，可用自己的 `pkgs.callPackage` 直接引用共用包定义，不导入 Linux 个人包导出清单。
- 根 flake 的 NixOS 模块列表统一先放 `profiles/base.nix`，紧接 `hosts/<主机名>`，再放其他 profile 和模块。
- 跨平台软件清单放 `common/packages.nix`，由 `nixos/modules/packages.nix` 和 `darwin/packages.nix` 引入，
  平台专属软件在各自清单中追加。共用 Nix 设置放 `common/nix.nix`。
- Linux 额外缓存优先配置在 `nixos/profiles/base.nix`。
- 不进系统配置的包安装到用户 profile。
