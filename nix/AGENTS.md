# Nix 配置

个人 NixOS flake：根目录 `flake.nix` 组装 `nixosConfigurations`（`hosts/` + `profiles/` + `modules/`），
包输出走 `pkgs/`。

## 目录结构

- `hosts/`: 各机器入口与 hardware-configuration
- `profiles/`: base / desktop 等组合
- `modules/`: NixOS 模块（真正系统级的配置：包列表、GNOME、zsh 等）
- `pkgs/`: 本地包与外部包的包定义

## 单包内聚

一个软件包的变更尽量内聚在 `nix/pkgs/<包名>/` 一个目录里，不要散落进 `flake.nix` / `modules/`：

- 包表达式用 `default.nix`（`nix/pkgs/default.nix` 里 `callPackage ./<包名>` 引用目录，不必写成 `./<包名>.nix`）
- 该包专属的资源都放同目录：补丁、图标、升级脚本（例：`qoder/update-qoder.sh`、`mark-shot/` 的补丁与 SVG）
- 需要外部 flake 输入的包：input 登记在根 `flake.nix`，包目录只放 `default.nix` 与资源（不自带 flake，
  如 `mark-shot/`），`pkgs/default.nix` 里以 `callPackage ./<包名> { flake = inputs.<包名>; }` 传入上游 flake，
  暴露成 `packages.<system>.<包名>`；不装进系统配置的用 `nix profile add path:~/.dotfiles#<包名>` 装进用户 profile
- 该系统级才能解决的问题才写进 `modules/`（例如所有用户都需要的包、systemd 单元）；单包能用包内机制解决的
  （wrapper、补丁等）优先内聚在包目录里

## 注意

- 根 flake 的 `inputs` 只能是字面量 attrset（`import` / `let` / `//` 都会被判为 thunk 而报错），
  外部输入只能直接登记在 `flake.nix` 的 input 块
- 不进系统配置的包用 `nix profile add path:~/.dotfiles#<包名>`（元素名即包名，用 `nix profile list` 查）；
  升级先在仓库根更新 `flake.lock`，再 `nix profile upgrade <包名>`；元素记录的是 `git+file:` URL 时
  要 `--override-flake '<原 URL>' "path:$REPO_ROOT"` 才取工作树（见 `pkgs/qoder/update-qoder.sh`）
