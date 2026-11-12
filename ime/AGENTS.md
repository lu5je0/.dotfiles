# 输入法（IM）工作指引

fcitx5 / Squirrel + Rime（雾凇拼音）的全部配置集中在本目录。

## 目录职责与 Nix 包

- `rime/`：个人 Rime 配置、Lua 与短语；`squirrel.custom.yaml` 仅供 macOS。
- `fcitx5/`：可写的 Fcitx5 用户配置，由 setup.py 的 `fcitx5` 模块整目录链接到 `~/.config/fcitx5`，
  避免 Fcitx5 保存设置时的 temp+rename 冲掉文件级链接。
- `themes/<name>/`：候选框主题，由 Nix 包安装到 `share/fcitx5/themes`。
- `environment.d/`、`autostart/`、`fontconfig/`：非 NixOS 环境可参考的桌面配置；
  使用时逐文件接入对应 XDG 目录。

Linux 独立包定义在 `nix/nixos/pkgs/fcitx5-rime/default.nix`，
通过 `.#fcitx5-rime` 导出，使用方法见同目录 `README.md`。
Nixpkgs 的 `rime-ice` 提供雾凇拼音、词库、Lua 和 OpenCC 数据，版本与哈希由根 flake 的
Nixpkgs 输入固定。包恢复上游 `default.yaml`，再叠加 `rime/` 下的 Linux 个人配置。
不在用户目录下载依赖，也不提供输入法安装脚本；setup.py 的 `fcitx5` 模块只链接 Fcitx5 用户配置。

包内 `share/rime-data` 只读，Rime 在用户目录 `~/.local/share/fcitx5/rime` 写入
`build/`、用户词库与学习数据。用户目录同名文件优先于共享数据，会遮蔽包内更新；
排查更新未生效时检查这些覆盖文件，处理时保留用户词库与学习数据。
不要将整个 Rime 用户目录链接到仓库或 Nix store。

`rime.lua` 与 `rime_ice.custom.yaml` 必须一起打包：后者引用
`lua_processor@ctrl_b_passthrough`，缺少 Lua 会导致方案加载失败。
macOS 配置源在 `rime/`，Squirrel 的部署与用户目录配置由用户管理。

## 部署注意

- **`rime/*.lua` 必须和 `*.custom.yaml` 一起 link**。`rime_ice.custom.yaml` 里 patch 了
  `lua_processor@ctrl_b_passthrough`，缺 lua 文件时 Rime 加载方案直接失败，表现为输入法完全不可用。
- **Debian + Wayland 下 `im-config` 是空操作**。`/etc/xdg/autostart/im-launch.desktop`
  执行 `im-launch true`，而 im-launch 里设置环境变量与启动守护进程的两个分支都要求
  `IM_CONFIG_PHASE=1`，该变量只由 `/etc/X11/Xsession.d/70im-config_launch` 设置，
  Wayland 会话不走 Xsession.d。所以环境变量（`environment.d/`）和自启（`autostart/`）
  都得自己管，`im-config -n fcitx5` 解决不了。
- **Chromium/Electron 应用要同时满足两个条件才有输入法**，缺一个都表现为
  「fcitx5 里完全没有这个应用的 input context」：
  1. 应用侧：Wayland 原生模式下不读 `GTK_IM_MODULE`/`XMODIFIERS`，必须命令行加
     `--enable-wayland-ime`；KWin 只实现 text_input v2/v3 而 Chromium 默认 v1，
     所以还要 `--wayland-text-input-version=3`。开关可通过应用 wrapper 或 desktop 的 `Exec` 传入；
     使用 desktop 覆盖时，在 `~/.local/share/applications/` 保留同名完整入口并调整相关 `Exec=`，
     保留 `MimeType`、`Actions`、`StartupWMClass` 与本地化名称，应用升级后核对上游入口变化。
  2. 合成器侧：`kwinrc` 的 `[Wayland] InputMethod` 必须指向
     `fcitx5-wayland-launcher.desktop`。没配时 `org.kde.kwin.VirtualKeyboard` 的
     `available` 为 `false`，KWin 不中转 text-input，加了 flag 也没用。
     Qt/GTK 应用不受这条影响 —— 它们靠 `*_IM_MODULE` 直连 fcitx5 的 D-Bus（`frontend:dbus`）。
     该 launcher 不会另起 fcitx5，只是把 KWin 给的 socket 通过 `OpenWaylandConnectionSocket`
     交给现有实例。**KWin 只在启动时读这个键，改完必须重新登录。**
- **某些 emoji 撑大候选框是字体回退问题，不是输入法**。打出 🛏(U+1F6CF) 等 emoji 时被黑白的
  `Noto Sans Symbols 2` 截胡、渲成宽扁字形；而 🛌 之类只有 `Noto Color Emoji` 有的正常。
  `fontconfig/75-noto-emoji-over-symbols2.conf` 在 scan 阶段从 Symbols 2 的 charset 中排除重叠 emoji，
  使其回退到 Color Emoji。接入或修改规则后执行 `fc-cache -f`；字体版本变化时重新核对码点集。

## 排查手法

判断某个应用有没有接上输入法，看它有没有 input context：

```sh
gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
  --method org.fcitx.Fcitx.Controller1.DebugInfo
```

- 列表里没有该应用 → 它压根没连上 fcitx5（查环境变量 / Chromium flag / KWin InputMethod）
- `frontend:dbus` → 走 `*_IM_MODULE` 直连，Qt/GTK 应用的正常形态
- `frontend:xim` → 走 XMODIFIERS/XIM，XWayland 应用的正常形态
- 全部为空且 `Group [...] has 0 InputContext(s)` → 会话级环境变量没生效

## 候选框皮肤

三套完全独立的配置，改一处不影响另一处；**关键是先分清当前候选框由谁绘制**：

| 场景 | 前端 | 皮肤配置 |
|---|---|---|
| Linux 非 GNOME（KWin 等）| fcitx5 classicui | `fcitx5/conf/classicui.conf` + `themes/` |
| **Linux GNOME** | **`kimpanel@kde.org` GNOME Shell 扩展** | GNOME Shell 弹出菜单主题（见下） |
| macOS | Squirrel | `rime/squirrel.custom.yaml` |

- **GNOME 下候选框不是 fcitx5 画的，classicui.conf 的 wechat 主题完全不生效**。
  fcitx5 只通过 kimpanel 的 DBus 把候选词喂给 `kimpanel@kde.org` 扩展，外观由该扩展绘制。
  它的 `stylesheet.css`（`~/.local/share/gnome-shell/extensions/kimpanel@kde.org/`）
  自己不设背景/文字色，用的是 Shell 标准类 `.popup-menu-boxpointer` / `.popup-menu-content`，
  所以**黑/白 = GNOME Shell 弹出菜单皮肤**。GNOME 47+ 起 Shell UI 跟随系统「浅色/深色」外观：
  `gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'` → 白，`'prefer-dark'` → 黑。
  固定候选框颜色可调整扩展的 `stylesheet.css`，但该文件不在本仓库，扩展升级会覆盖修改。

主题注意：

- **主题缺失会回退到内置样式**。`classicui.conf` 引用的主题需要随部署安装；仓库主题位于 `themes/`，
  使用外部主题时同时声明安装依赖。
- **主题读的是 data 目录**（`~/.local/share/fcitx5/themes/`），不是 `~/.config/fcitx5/`。
- **Rime 颜色是 `0xAABBGGRR`（BGR 序），fcitx5 是 `#RRGGBB`**，转换时交换红蓝通道。
  例如 squirrel 的 `0x75B100` 对应 `#00B175`。
- 当前主题通过 9-patch 背景图提供圆角，`Background/Margin` 保留四角，中间区域拉伸。
- **配了 `Image=` 之后 `BorderWidth`/`BorderColor` 完全不生效**。fcitx5 的
  `ThemeImage` 构造函数里画边框的代码包在 `if (!image_) { ... }` 里（`src/ui/classic/theme.cpp`），
  背景图加载成功后跳过该分支，因此圆角边框由背景图自身绘制。
- **背景图使用 SVG**（`themes/*/panel.svg`、`highlight.svg`），修改 `rx` / `fill` 即可。
  `Background/Margin` 无论 PNG 还是 SVG 都必须 >= 圆角半径，否则拉伸区切进圆角。
- 小数缩放可能使描边落在非整数物理像素上，产生抗锯齿。需要控制物理宽度时，可用外层边框色矩形与
  内层背景色矩形绘制，内缩量按目标物理像素数除以缩放计算，并在目标显示环境验证。
- SVG 是否按矢量重绘取决于 Fcitx5 构建；原生 SVG 路径使用 librsvg，图像加载后端也可能先栅格化再缩放。
  排查清晰度时检查实际加载路径。
- **`Highlight/Margin` 是一个键干两件事**：它既是 9-patch 的拉伸边界（所以高亮图的圆角必须 <= 它，
  否则圆弧被拉伸区切开），也是绿块相对候选文字向外扩张的量（`inputwindow.cpp` 里
  高亮矩形 = 候选文字盒 ± 该 margin）。圆角与高亮外扩需要一起调整；竖直内边距还受字体度量影响。
- **面板留白和候选之间的间距共用 `TextMargin`**：
  面板边→绿块 = `ContentMargin + TextMargin − Highlight/Margin`，
  候选间距 = `TextMargin.Left + TextMargin.Right − Highlight/Margin`。
  想让绿块和面板的圆角看起来「对得上」，按同心圆取：
  `高亮圆角 = 面板圆角 − 面板边到绿块的间距`（当前 4 = 10 − 6），两条圆弧才平行。
- 主题未声明 `[AccentColorField]` 时，`UseAccentColor=True` 不会覆盖主题颜色。

## 本目录之外的相关配置

- `nix/nixos/modules/fcitx5.nix` 为所有 NixOS desktop 主机安装 Fcitx5、WeTypeX 和 GTK 输入模块，默认输入法为 WeTypeX，不默认安装 Rime；独立 Rime 包提供雾凇与个人配置，本目录保留用户配置源和主题。
- `wm/niri/config.kdl` 里有 `spawn-at-startup "fcitx5" "-d" "--replace"`（niri 的自启，不走 XDG autostart）。
- `module/tui-bridge/linux/im.c` 通过 DBus 调 `org.fcitx.Fcitx.Rime1` 切 rime 的 ascii_mode，
  供 Neovim 用；改 rime 方案时注意别动 `ascii_mode` 开关的语义。
