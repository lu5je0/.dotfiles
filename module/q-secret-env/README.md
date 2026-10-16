# q-secret-env

加密保存环境变量。`bin/common/q-secret-env` 是轻量入口，实现位于本目录的
`q-secret-env.py`，依赖 Python 3.9+ 标准库，以及支持 `enc -pbkdf2` 的 OpenSSL。
不需要安装 Python 第三方库或虚拟环境。

```sh
q-secret-env --help
q-secret-env passwd
q-secret-env set EXAMPLE_TOKEN                 # 隐藏输入
q-secret-env set EXAMPLE_TOKEN 'example-value'
printf '%s' "$TOKEN" | q-secret-env set EXAMPLE_TOKEN --stdin
q-secret-env get EXAMPLE_TOKEN
q-secret-env list
q-secret-env list --values
q-secret-env unset EXAMPLE_TOKEN
q-secret-env sync
q-secret-env unlock
```

无参数显示帮助，各子命令支持 `--help`；参数解析及帮助由 `argparse` 生成。
成功退出码为 0，运行失败为 1，参数错误为 2。stdout 只输出数据和帮助，
保存、删除、密码更新等提示写入 stderr。

`set NAME` 在交互终端隐藏输入，允许空值；非交互环境必须提供 `VALUE` 或 `--stdin`。
`VALUE` 与 `--stdin` 互斥，后者保留所有内容，包括末尾换行。值以 `-` 开头时使用
`q-secret-env set NAME -- '-value'`。环境变量名必须合法，值不能包含 NUL。

## 读取与缓存

- `list` 只读明文索引，无需密钥，不创建配置目录；适用于 zsh 变量名补全。
  没有索引的旧密文格式会提示使用 `list --values`。
- `get`、`list --values` 解密后输出，不修改密文、密钥或 `env.zsh`，
  读取旧格式时也不自动迁移。
- `set`、`unset` 修改密文并自动更新本地 `env.zsh`。
- `sync` 根据本地密文重新生成缓存，不执行 Git 同步。
- `unlock` 验证主密码，保存本地解密凭据并刷新已有密文的缓存。

要让当前终端立即使用新值，执行 `source ~/.config/q-secret-env/env.zsh`。
从其他机器拉取密文后，当前终端先执行 `q-secret-env sync`，再加载缓存。

## 存储与兼容

- 密文：`${DOTFILES_DIR:-$HOME/.dotfiles}/secrets/q-secret-env.enc`。
- 本地密钥：`${XDG_CONFIG_HOME:-$HOME/.config}/q-secret-env/master.pass`。
- 明文导出缓存：同目录的 `env.zsh`。
- 自动迁移旧目录 `~/.config/lu5je0/q-secret-env`（遵循 `XDG_CONFIG_HOME`）。
- 兼容原 Bash 实现的 `QSENVENC1`、`QSENVENC2` 和原始 OpenSSL 密文，
  以及 `QSENV1`、`QSENV2` 和旧明文密码文件。写入统一使用 `QSENVENC2`。
- 保留 AES-256-CBC、PBKDF2 和原有密码派生规则；环境变量名仍是明文索引。
  本地密钥和 `env.zsh` 都是敏感文件，不能上传。

加解密数据在内存中处理，传给 OpenSSL 的密码通过文件描述符提供，不进入命令行参数。
密文、密钥及缓存以权限 `0600` 的临时文件原子替换，配置目录权限为 `0700`。
空值、引号、中文和末尾换行可往返保存，导出文件可供 Bash/zsh 加载。

`zsh/secret-env.zsh` 的缓存判断保持原样：正常启动只加载 `env.zsh`，
仅当密文更新或缓存缺失时才启动 Python 执行 `sync`。

## 验证

在仓库根目录运行，测试只使用临时目录和假密码：

```sh
python3 -m unittest discover -s module/q-secret-env/tests -v
```
