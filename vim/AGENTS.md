# Neovim 配置工作指引

## 范围与维护

- 适用于 `vim/`；修改子目录前阅读其中的 `AGENTS.md`，跨目录联动时同时阅读对应说明。
- 修改本文声明的结构、约束、加载方式或验证入口时同步更新本文，只记录当前行为和必要的设计原因。
- 保持模块边界与懒加载方式，优先做最小改动；Lua 格式遵循 `stylua.toml`。
- 涉及桥接协议、IME、剪贴板或二进制同步时，同时检查仓库根目录的 `module/tui-bridge/AGENTS.md`。

## 结构与装配

- `init.lua` 先启用 `vim.loader`、加入 lazy.nvim 运行时路径，再依次加载 `lu5je0.options`、`keymaps`、`plugins`、`ext-config`、`commands`、`autocmds`、`filetype`。各模块通过 `pcall(require, ...)` 加载，失败时通知但继续启动。
- `lua/lu5je0/plugins.lua` 集中声明第三方插件、依赖、补丁与插件级配置；适配代码放在 `ext/`。
- `ext-config.lua` 声明本地扩展，由 `ext/loader.lua` 按 `keys`、`cmd`、`event` 代理首次加载并回放操作。
- `core/` 放共享能力，`misc/` 放独立工具，`lang/` 放轻量函数；新功能通过明确的装配入口接入。
- 文件类型定制放在 `ftplugin/`、`after/` 等运行时目录；LSP 修改同时检查 `lsp/` 和 `core/lsp.lua`。
- `core/filetree.lua` 通过 Sidebar Files 页打开目录，注册 `Plugins`、`SwapFiles`、`TimeMachine`，由 sidebar 条目懒加载；插件和 swap 路径分别取自 `stdpath('data')`、`stdpath('state')`。
- `misc/lsp-info.lua` 只在执行 `:LspInfo` 时加载；命令由 nvim-lspconfig 的 `cmd` 懒加载入口注册。
- `lib/` 的 native 资源按平台组织，通过 `core/native.lua` 解析；调整位置时检查外部消费脚本和构建同步逻辑。

## 插件加载与补丁

- 基础编辑行为放在 `options.lua`、`keymaps.lua`、`autocmds.lua`、`commands.lua`；第三方插件行为优先放在对应 spec 或适配文件中。
- Markdown 依赖由 `ftplugin/markdown.lua` 直接调用 `lazy.load`，避免 lazy 的 `FileType` 重放重复初始化语法。render-markdown 保持 `lazy = true`，Snacks 保留供其他功能使用的 `VeryLazy`。
- Lua 依赖由 `ftplugin/lua.lua` 直接加载 lazydev 和 colorizer，并显式挂载 colorizer 到当前 buffer，避免错过正在派发的 `FileType`。lazydev 保持 `lazy = true`；colorizer 的配置仍包含 Lua，但 spec 的 `ft` 排除 Lua，其他文件类型保持按需加载。
- Scrollview 由 normal 模式 `<leader><Tab>` 首次加载，默认关闭，按键启用五秒、再按可提前关闭。setup 必须先完成上游延迟的命令初始化，才能回放首按。
- 插件 spec 的 `keys` 不得使用裸 `<leader>`：lazy 代理会占用该键，阻止 which-key 安装触发器；使用实际功能键，如 `<leader>ff`。
- 改插件版本、来源或锁定策略时检查 `lazy-lock.json`；仅在必要时调整 `disabled_plugins`，它直接改变运行时插件集合。
- `nixd` 由 Nix 的 `nix/common/packages.nix` 安装，不经 Mason；`core/lsp.lua` 检查 PATH 后启用，配置在 `lsp/nixd.lua`。
- 补丁文件放在 `patches/`，与 spec 的 `patches` 声明同步维护；只支持修改现有 `lua/**/*.lua` 模块，不支持增删、重命名模块或修改其他运行时文件。
- `ext/lazy_patch.lua` 在 `lazy.setup()` 前注册，通过 `LazyPlugins` 读取解析后的 spec 和插件目录，再用 `package.preload` 覆盖模块，保留首次加载与配置语义。
- 首次 require 时复制受影响源码，在 `stdpath('cache')/lazy-patches/<内容哈希>/` 应用补丁；哈希包含源码、插件目录和补丁内容，暖缓存不调用 Git。生成使用临时目录并原子发布，应用或语法检查失败直接报错，不回退原模块、不修改插件工作树。
- `:LazyApplyPatch` 主动准备缓存但不热重载；修改补丁后重启 Neovim。恢复版本用 `Lazy restore`；根目录 `lazy-restore.sh` 使用阻塞的 `Lazy! restore` 后更新 parser。
- `lazy-restore.sh` 的原地补丁兼容段只撤销可完整反向应用的已知补丁，保留其他本地修改；所有环境改用缓存补丁后删除该兼容段。
- Glance 补丁仅静默 nixd 的 `unknown node type for definition`；只有全部客户端响应均为该错误时才跳过 `No definitions found`，其他错误、空结果和正常结果保留原行为。

## Multicursor

- 能力探测统一使用 `require('lu5je0.ext.multicursor').supported`，由 `core/multicursor-guard.lua` 先检查 `follow` 选项，再加载 `vim._core.mcursor` 并检查 `active`；不能只检查版本号或 `nvim_mcursor`。
- 0.12 使用 vim-visual-multi，原生适配层保持 no-op 的 `setup()`；0.13+ 使用原生能力。仓库不再支持 0.12 时可移除兼容插件及其 spec、配置和按键。
- 原生 cursor 使用 normal-mode 语义；`<C-n>`、`<M-n>`、`\A` 完成后开启 follow。添加或移动 cursor 的主体必须 `vim.schedule` 出 typed CmdAtom，避免 LHS replay 级联；移动 primary 前用 `2q=` 关闭 follow，完成后用 `1q=` 恢复。
- `<C-n>` 连按复用首次 pattern，`<C-n>` / `\A` 同时写入 `@/` 和 `session_patterns`；保留整词边界，不能随光标变化重新取词。
- x-mode 回调通过 `vim.fn.mode()` 判断选区类型，不能依赖此时为空的 `visualmode()`；退出选区后显式使用左上角位置。
- `<C-l>`、`<C-p>`、`<C-x>` 仅在会话中挂 buffer-local 映射，结束时恢复原映射。比较 `nvim_buf_get_keymap()` 的 lhs 时处理大小写和 `<leader>` 展开。
- 不在正在执行的映射回调里卸载自身；先保存待恢复状态，由 scheduled `sync_cl_map` 重判 `mc.active()` 后处理。清 namespace 后等待一拍再开始下一次测试。
- 系统剪贴板粘贴保持全局 `<leader>p` / `<leader>P` 的 `"*p` / `"*P` 字符串映射；隐式 clipboard 或 Lua 函数代理会导致只有 primary 生效。
- gitsigns / DiffBase 直接调用共享保护模块的 `preserve(action)`，不依赖按键适配层；reset 只执行一次，保留当前 hunk 的操作范围。
- 受保护的同步或异步编辑必须调用 `done(err)`；保护层修正 cursor 位置并恢复 follow，通过 session hooks 保存/恢复 pattern，且不得在用户取消会话后重新创建光标。
- 不在 `ModeChanged` 中切换 `showcmd`，避免暴露原生 cursor 的重画中间态。

## Winbar 与共享状态

- 状态栏仅查询已加载的 navic / DiffBase，未命名 buffer 从 `winbar.state` 读取名称，避免重复 setup；navic 的 `LspAttach` 监听需使用独立 augroup，确保首次懒加载时事件能回放。
- 自定义窗口 buffer 标签位于 `ext/winbar/`，通过 `vim.wo.winbar` 渲染；`ext/winbar.lua` 和 `ext/bufferline.lua` 都是调用其 setup 的入口。
- 修改窗口标签时先读 `lua/lu5je0/ext/winbar/agents.md`；高亮、拖动、截断和关闭 buffer 的约束集中在该文件。
- 调整 buffer 名称映射或 `core/buffers.lua` 时检查 sidebar、winbar、time-machine 的消费方；修改 offset 时考虑窗口 separator、foldcolumn 和 signcolumn 宽度。

## 平台与 TUI Bridge

- 剪贴板入口为 `misc/clipboard/init.lua`：SSH 使用 OSC52，macOS 使用 FFI，WSL / Linux 桌面使用 native tui-bridge。
- tui-bridge 的 `+` 是 CLIPBOARD，仅在启动 / FocusGained 同步缓存；`*` 是 primary selection，每次实时读写、不得复用缓存。`core/clipboard.lua` 的 `M.set` 只写 `+`，避免覆盖外部鼠标选区。
- IME 入口为 `misc/ime/init.lua`：macOS 使用 XkbSwitchLib，WSL / 非 SSH 的 Linux 桌面使用 tui-bridge；`TERM=xterm-kitty` 优先使用 OSC，未匹配环境和 Linux SSH 也回退 OSC。
- IME 按模式、输入上下文和焦点/窗口事件同步，不监听手动切换；临时输入 UI 使用 `set_typing_context(name, active)`，避免 preview 切窗时误关 IME。
- OSC 在 tmux 中需包装为 passthrough 序列并加倍内层 ESC，依赖 `tmux/tmux.conf` 的 `allow-passthrough on`；`zsh/vi-im-switch.zsh` 使用相同包装。
- installer 读取 `module/tui-bridge/VERSION`，安装到 `~/.local/bin/tui-bridge`；支持 macOS、Linux x86_64/aarch64 和 WSL x86_64。WSL 下载 Windows 产物，Linux arm64 映射为 aarch64。
- 仅启用后端、实际调用或执行 `:TuiBridgeInstall` 时安装，加载模块与退出不下载；版本检查、下载和校验均异步，校验 SHA256 与 `--version` 后原子替换，安装锁协调多进程。
- `singleton()` 只返回对象，`on_ready()` 后才接管剪贴板与 IME，未就绪时不重放请求；IME 就绪后调用 `resync()`。
- WezTerm 共用安装路径和版本声明；Windows 端通过 `wslpath -w` 定位默认 WSL 发行版中的安装，仅检查版本、不负责下载。

## 测试与验证

- 最小启动检查：`cd vim && nvim --headless '+qa'`。
- 自动化入口：`cd vim && ./tests/run-tests.sh`；具体用例及参数以脚本和测试文件头部为准，cron 用例通过脚本设置 `DOTFILES_ROOT`。
- 新增具备稳定输入输出的独立 Lua 功能时补测试；修改懒加载模块至少验证一次对应命令、按键或事件的首次加载路径。
- 子进程测试隔离配置、状态、swap 和 shada；使用真实插件时禁用自动安装/更新，不修改插件工作树。
- 原生 multicursor 测试需用 0.13+ 运行外层和子进程，0.12 按能力探测 SKIP；`NVIM_TEST_BIN` 不能把 0.12 外层升级为 0.13。使用 `nvim_input()` 发真实按键，脚本中的 `feedkeys(..., 'x')` 不覆盖 typed CmdAtom 行为。
- which-key 的首次触发测试使用 pty TUI + `--listen` / RPC，确保 `UIEnter` 和 `VeryLazy` 执行；鼠标与 winbar UI 测试的要求见局部说明。
- 补丁验证同时检查声明、缓存生成和实际加载行为；平台改动需注明已验证和未验证的平台。

## 临时兼容

- `core/buffer-modified.lua` 在 0.12 同时注册 `BufModifiedSet`（自然编辑）和 `OptionSet modified`（显式设置），0.13 仅保留后者。winbar 和 sidebar 都必须通过它订阅，不能省略 modified 通知。运行环境切换到 0.13 正式版、`BufModifiedSet` 不再存在时，删除兼容层并将两处调用替换为独立的 `OptionSet` + `pattern = 'modified'` autocmd；该事件延迟派发，不能混入无需 pattern 的事件列表。
- `autocmds.lua` 在 0.12 使用 `vim.hl.on_yank`，0.13+ 使用 `vim.hl.hl_op`。不再支持 0.12 时删除分支，直接调用 `hl_op`。
