# q-trash 工作指引

## 实现与平台
- `src/main.rs`：`list` / `ls` / `restore` / `empty` / `size` 命令和参数解析。
- `src/rm.rs`：rm 兼容参数、交互与校验；`--purge` 才永久删除。
- `src/freedesktop.rs`：Linux 回收站发现、trashinfo 与同卷移动；不做跨卷拷贝。保持与 trash-cli 互通。
- `src/windows.rs`：WSL Windows 原生盘通过 PowerShell 回收，扫描 `$Recycle.Bin` 元数据；主程序仍为 Linux 二进制。
- `src/macos.rs` / `src/macos.m`：通过 Foundation 原生回收；读取 `.DS_Store` put-back 记录供恢复。Objective-C shim 使用 ARC 和 autorelease pool，仅跨 FFI 返回 malloc-owned 错误字符串。
- `src/util.rs`：原生路径字节、时间、资源操作；最终移动使用不覆盖目标的原子 rename；Linux 直接通过 syscall 调用 renameat2，兼容 musl 静态链接。不能退化成先检查再普通 rename。
- 路径使用 `PathBuf` / `OsString`，仅显示时允许有损转换。Linux trashinfo 路径按原始字节做百分号编码。
- 只支持 Linux（含 WSL）和 macOS；没有原生 Windows 或 Android/Termux 产物。

## 构建与安装
- `Cargo.toml` 是版本号唯一来源；提交 `Cargo.lock`。`cargo build --release` 构建，无 Python 运行时依赖。
- Nix 包定义保留一份，位于 `nix/nixos/pkgs/q-trash/default.nix`；NixOS / nix-darwin 通过共用软件清单，用各自平台的 `pkgs.callPackage` 构建安装。`nix/nixos/pkgs/default.nix` 只登记 x86_64-linux 的独立构建入口，ARM Linux / Darwin 的系统安装不依赖此导出。
- Nix 与 setup 均提供 `q-trash`，zsh 按现有 PATH 顺序查找；`~/.local/bin` 优先，`safe_rm` 继续调用 `q-trash rm`。
- setup.py 的 q-trash 模块通过 `scripts/setup.d/modules/unix/q-trash.sh` 安装固定版本的 GitHub Release 到 `~/.local/bin/q-trash`；SHA256 和候选文件版本均验证成功后原子替换，失败保留旧版本。
- `.github/workflows/build-q-trash.yml` 构建 Linux x86_64 / aarch64 的 musl 静态产物和 macOS aarch64 原生产物。`q-trash-v<VERSION>` tag 与 Cargo 版本一致时发布；普通分支和手动运行只构建验证。
- 调整 CLI 时同步检查 `zsh/completions/_q-trash` 和 README；修改安装契约时同步 setup 模块定义与 Nix 包。

## 验证
- `cargo test`，`cargo build --release`。
- `QTRASH_BIN=/absolute/path/to/q-trash python3 tests/run_compare.py`：GNU rm 行为对照；macOS 通过 `QTRASH_SYSTEM_RM` 指定 GNU rm。
- 同样指定 `QTRASH_BIN` 运行 `tests/run_qtrash.py`、`tests/run_safety.py`；默认使用 `target/debug/q-trash`。
- `python3 tests/run_installer.py` 验证下载校验、失败保留与 zsh 的 PATH 选择，无网络请求。
- `python3 -m pytest tests/test_qrm.py` 补充 rm 测试与 trash-list 互通（需安装 pytest 和 trash-cli）。
- Linux 测试清除 XDG_DATA_HOME，使用临时 HOME 隔离回收站；macOS 原生测试只能在真实用户会话中运行，清理严格限制为测试 sandbox 原路径下的项目，Nix sandbox 不运行这些原生测试。
