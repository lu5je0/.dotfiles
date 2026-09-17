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

## 二进制缓存

`profiles/base.nix` 的 `nix.settings` 里加了 nix-community 的 cachix（第三方只读公开缓存），
用于 nightly 类包（如 neovim-nightly-overlay）避免本地编译。

- **只列额外缓存，不要再写 `cache.nixos.org`**：nixpkgs 的 `nixos/modules/config/nix.nix` 已经在
  `config` 段里默认定义了 `substituters = mkAfter [ "https://cache.nixos.org/" ]` 与
  `trusted-public-keys = [ "cache.nixos.org-1:..." ]`。`nix.settings` 的 list 类型是**合并**语义（不是覆盖），
  重复列会得到两份。要验证：`nix eval --json .#nixosConfigurations.<host>.config.nix.settings.substituters`。
- **优先加系统级 `substituters`，而不是信任 flake 的 `nixConfig`**：替换按路径哈希全局进行，缓存已在
  全局列表就不需要 flake 提权。给 `trusted-users` 加 `@wheel` 等于允许任意 flake 指定任意缓存，
  权限面比这个小得多（Nix 手册：`substituters` 只要求「在 `trusted-substituters` 里」或「调用者在 `trusted-users` 里」）。
- 改了系统配置后现行 shell 的 `nix.conf` 不会变，要 `sudo nixos-rebuild switch` 才生效；
  临时验证可用 `nix build --substituters ...` 或 `--option`。
- 缓存不保证命中（nightly 每天一个 commit，缓存里不一定有那一版），命不中就本地编译。

## 注意

- 根 flake 的 `inputs` 只能是字面量 attrset（`import` / `let` / `//` 都会被判为 thunk 而报错），
  外部输入只能直接登记在 `flake.nix` 的 input 块
- 不进系统配置的包用 `nix profile add path:~/.dotfiles#<包名>`（元素名即包名，用 `nix profile list` 查）；
  升级先在仓库根更新 `flake.lock`，再 `nix profile upgrade <包名>`；元素记录的是 `git+file:` URL 时
  要 `--override-flake '<原 URL>' "path:$REPO_ROOT"` 才取工作树（见 `pkgs/qoder/update-qoder.sh`）
