# q-trash

Rust 编写的回收站工具，支持 Linux、WSL 和 macOS。提供 `rm` 兼容入口及回收站管理，无 Python 运行时依赖。

```sh
q-trash rm file
q-trash rm -rf directory
q-trash rm --purge file          # 永久删除
q-trash list                     # 别名 ls
q-trash list .                   # 按原路径筛选
q-trash restore /path/to/file     # 恢复最新的精确匹配
q-trash restore --all .
q-trash restore --dest /tmp/new-name /path/to/file
q-trash empty --days 30           # 确认后永久删除
q-trash size --current-disk
```

`rm` 支持 `-f -i -I -r -R -d -v --interactive[=WHEN] --preserve-root --no-preserve-root --one-file-system --`，默认送入回收站，`--purge` 才真删。交互式 zsh 的 `rm` 已由仓库 `safe_rm` 接入。

## 安装

NixOS / nix-darwin 通过共用软件清单，用各自平台的 Nixpkgs 构建安装同一份 Rust 包定义。x86_64 Linux 也可从仓库根目录独立构建或安装到用户 profile：

```sh
nix build path:.#q-trash
nix profile add path:.#q-trash
```

ARM Linux / macOS 通过各自的系统配置安装，不依赖 Linux 个人包导出清单。Nix 与 setup 均提供 `q-trash`，按现有 PATH 顺序选择；`~/.local/bin` 中的可执行版本优先于 Nix 路径。

其他 Linux / WSL / macOS 机器通过根目录 `setup.py` 的 q-trash 模块下载固定版本，也可手动运行：

```sh
bash scripts/setup.d/modules/unix/q-trash.sh
```

安装器根据系统与架构下载 GitHub Release，校验 SHA256 和版本后原子替换 `~/.local/bin/q-trash`。WSL 使用 Linux 产物；预编译版本仅覆盖 Linux x86_64 / aarch64 和 macOS aarch64，Android/Termux 和原生 Windows 暂不支持。

源码构建：

```sh
cd module/q-trash
cargo build --release --locked
./target/release/q-trash --help
```

macOS 构建需 Xcode Command Line Tools；其他平台仅使用 Rust 和系统 C 工具链。

## 平台行为

- **Linux**：freedesktop Trash Spec 1.0；同卷优先 `$XDG_DATA_HOME/Trash`，其他卷优先 sticky 且非符号链接的 `$top/.Trash/$UID`，否则 `$top/.Trash-$UID`。不跨卷拷贝，无法回收时报错。`files` 与 `info` 目录要求当前用户所有、无组/其他用户权限且非符号链接。支持非 UTF-8 文件名，与 `trash-list` / `trash-restore` 互通。
- **WSL**：`drvfs` / `9p` / `virtiofs` 上的 Windows 路径调用 PowerShell 的 Windows 回收站 API，Windows 资源管理器可还原；Linux 路径仍使用 freedesktop。管理命令扫描各盘 `$Recycle.Bin`。
- **macOS**：调用 Foundation `NSFileManager trashItemAtURL:`，保留系统 put-back 元数据；扫描 `~/.Trash` 和 `.DS_Store`。Finder put-back 记录可能延迟写入，未知原路径的项目需指定 `restore --dest`。终端读取回收站可能需要 Full Disk Access。

`list` / `restore` / `empty` / `size` 支持 `--current-disk`。`--trash-dir DIR` 可指定一个 freedesktop 格式回收站；不改变 `rm` 写入目的地。恢复默认不覆盖已有目标；`--overwrite` 明确允许覆盖。

## 发布与验证

版本唯一来源为 `Cargo.toml`。推送 `q-trash-v<VERSION>` tag 后，GitHub Actions 原生构建并验证三个产物，再发布 Release：

- `q-trash-linux-x86_64`、`q-trash-linux-aarch64`：musl 静态链接。
- `q-trash-macos-aarch64`：使用系统 Foundation。
- `SHA256SUMS`。

分支推送、PR 和手动运行只构建测试，不发布。

```sh
cargo test --locked
cargo build --locked
python3 tests/run_compare.py
python3 tests/run_qtrash.py
python3 tests/run_safety.py
python3 tests/run_installer.py
python3 -m pytest tests/test_qrm.py
```

测试可通过 `QTRASH_BIN` 指定 release 或 Nix 产物。`run_compare.py` 要求 GNU rm，macOS 可通过 `QTRASH_SYSTEM_RM` 指定 `grm`；pytest 测试中的 trash-cli 互通验证需要 `trash-list`。Linux 用临时 HOME 隔离，macOS 测试使用系统回收站并仅清理测试路径下的条目。
