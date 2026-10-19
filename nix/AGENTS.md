# Nix 配置

## 包组织

- 主机专用包放 `hosts/<主机名>/pkgs/<包名>/`，由主机配置就近引用；多台主机共用后才移入
  `pkgs/<包名>/`，并在 `pkgs/default.nix` 登记。
- 主机专用包需要导出 flake 构建入口时，根 flake 直接引用主机目录，不为导出而搬进共用目录。
- 包表达式用 `default.nix`；补丁、图标、升级脚本放同目录。
- 单包能通过 wrapper、补丁等解决的问题留在包内，系统级配置才放进 `modules/`。
- 包需要外部 flake 时，在根 `flake.nix` 登记 input，通过 `callPackage` 参数传入，包目录不自带 flake。

## 配置归属

- 额外缓存优先配置在 `profiles/base.nix`。
- 不进系统配置的包安装到用户 profile。
