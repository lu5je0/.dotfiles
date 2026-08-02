# 输入法（IM）工作指引

fcitx5 / Squirrel / Weasel + Rime（雾凇拼音）的全部配置集中在本目录。

## 目录职责

| 路径 | 目标 | link 方式 |
|---|---|---|
| `fcitx5/` | `~/.config/fcitx5` | 整目录 |
| `rime/` | `~/.local/share/fcitx5/rime`（mac 为 `~/Library/Rime`） | 逐文件 |
| `environment.d/*.conf` | `~/.config/environment.d/` | 单文件 |
| `autostart/*.desktop` | `~/.config/autostart/` | 单文件 |
| `themes/<name>/` | `~/.local/share/fcitx5/themes/<name>` | 整目录 |
| `install.sh` | Linux / macOS 安装入口 | — |
| `install.bat` | Windows（Weasel）安装入口 | — |

`install.sh` 另外还写 `kwinrc` 的 `[Wayland] InputMethod`（见下）。

## 上游 rime-ice 在哪里

**不是 submodule。** 安装时由 `install.sh` 浅克隆到 **Rime 用户目录**：

```
~/.local/share/fcitx5/rime/          ← RIME_DIR（mac: ~/Library/Rime）
├── rime-ice/                        ← git clone --depth 1，上游雾凇拼音
├── default.yaml -> rime-ice/default.yaml        上游：**相对**链接
├── cn_dicts     -> rime-ice/cn_dicts
├── rime.lua     -> ~/.dotfiles/ime/rime/rime.lua  个人：**绝对**链接
└── build/ installation.yaml user.yaml            Rime 运行时数据
```

为什么不用 submodule：

- rime-ice 词库改动频繁，完整历史的 `.git` 有 **232M**（工作树才 50M），全压在 dotfiles 里不值。
  浅克隆后 `.git` 只 **17M**。
- 它是上游运行时数据，不是你的配置；你的配置只有 `rime/` 下那几个 `*.custom.yaml` / `*.lua` / `custom_phrase.txt`。
- 放在 RIME_DIR 而不是仓库里，仓库目录就不会嵌一个外来 git 仓，`git clean -xdf` 也不会误删它。

上游文件用**相对**链接（`rime-ice/xxx`），因为 rime-ice 就在同一目录里，整个 RIME_DIR 搬走也不会断；
个人定制用**绝对**链接，因为要指回仓库。

更新上游（浅克隆不能直接 `git pull`）：

```sh
cd ~/.local/share/fcitx5/rime/rime-ice
git fetch --depth 1 origin && git reset --hard origin/HEAD
```

重跑 `install.sh` 不会拉更新 —— 只有 `rime-ice/default.yaml` 不存在时才 clone。
目录存在但缺 `default.yaml` 时脚本会报错退出而不自动删，避免误删你放在里面的东西。

**它不碰 `~/.local/share/applications/` 下的 desktop 文件**。早期版本会从系统 desktop
生成一份覆盖并追加 flag，但那意味着每次重跑都 `rm -f` 后重写，会吞掉手改内容；
现在这些文件完全由你手动维护，dotfiles 不接管。

安装由 `scripts/setup.d/modules/{unix,win}/modules.json` 的 `rime-ime` 模块触发，
分别调用 `ime/install.sh` 与 `ime/install.bat`（对应 `rime-ime.sh`）。脚本幂等，可重复执行。

## 为什么 link 方式不统一

- **`fcitx5/` 整目录**：这个目录只有 fcitx5 在用。fcitx5 保存设置时用 temp+rename，
  会把文件级软链接冲成实体文件；整目录 link 才能让设置界面里的改动落回仓库。
- **`rime/` 逐文件**：Rime 会在用户目录里写 `build/`、`installation.yaml`、`user.yaml`
  等运行时数据，整目录 link 会把这些垃圾灌进仓库。
- **其余两个共享 XDG 目录单文件**：`environment.d` / `autostart`
  是多个程序共用的，整目录 link 会挡住别的程序往里写。
  `~/.local/share/applications` 同理，而且里面的 desktop 覆盖干脆不由本仓库管。

## 几个必须知道的坑

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
     所以还要 `--wayland-text-input-version=3`。这些开关只能落在 desktop 的 Exec 上
     （VS Code 系的 `argv.json` 白名单不含它们，环境变量也传不进去）。
     **这一步需要手工做**：把 `/usr/share/applications/<app>.desktop` 拷到
     `~/.local/share/applications/`（同名即覆盖），给每一条 `Exec=` 加上开关。
     拷整份而不是写个精简版：`Exec` 不只一条（Chrome 有普通/新窗口/隐私三条），
     而且 `MimeType`（默认浏览器关联）、`Actions`、`StartupWMClass`、上百行本地化
     `Name[..]` 都不能丢。应用升级后如果上游 desktop 变了，要自己重新拷一份。
  2. 合成器侧：`kwinrc` 的 `[Wayland] InputMethod` 必须指向
     `fcitx5-wayland-launcher.desktop`。没配时 `org.kde.kwin.VirtualKeyboard` 的
     `available` 为 `false`，KWin 不中转 text-input，加了 flag 也没用。
     Qt/GTK 应用不受这条影响 —— 它们靠 `*_IM_MODULE` 直连 fcitx5 的 D-Bus（`frontend:dbus`）。
     该 launcher 不会另起 fcitx5，只是把 KWin 给的 socket 通过 `OpenWaylandConnectionSocket`
     交给现有实例。**KWin 只在启动时读这个键，改完必须重新登录。**

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

三个平台的皮肤是三套完全独立的配置，改一处不会影响另两处：

| 平台 | 前端 | 皮肤配置 |
|---|---|---|
| Linux | fcitx5 classicui | `fcitx5/conf/classicui.conf` + `themes/` |
| Windows | Weasel | `rime/weasel.custom.yaml` |
| macOS | Squirrel | `rime/squirrel.custom.yaml` |

坑：

- **主题缺失是静默失败**。`classicui.conf` 里的 `Theme=` 指向一个本机没装的主题时，
  fcitx5 直接退回内置样式，**日志里一个字都不会报** —— 表现就是「皮肤看起来很奇怪」。
  所以主题必须放 `themes/` 由仓库自带，不要引用外部下载安装的主题名。
- **主题读的是 data 目录**（`~/.local/share/fcitx5/themes/`），不是 `~/.config/fcitx5/`。
- **Rime 颜色是 `0xAABBGGRR`（BGR 序），fcitx5 是 `#RRGGBB`**，直接照搬数字会得到错色。
  例：squirrel 的 `0x75B100` → `#00B175`。验证方法：rime-ice 的 `squirrel.yaml` 里
  solarized 配色 `back_color: 0xF0E5F6FB` 按 BGR 解出 `#FBF6E5`，与 Solarized base3 `#FDF6E3` 吻合。
- **fcitx5 主题没有 `BorderRadius`**（至少 5.1.12 没有，已在所有 `libFcitx5*` 里搜过）。
  圆角只能靠 9-patch 背景图，配 `Background/Margin=10` 保住四角、中间拉伸。
- **配了 `Image=` 之后 `BorderWidth`/`BorderColor` 完全不生效**。fcitx5 的
  `ThemeImage` 构造函数里画边框的代码包在 `if (!image_) { ... }` 里（`src/ui/classic/theme.cpp`），
  背景图加载成功就永远进不了那个分支。所以**边框也必须烘进 PNG**，
  而且就算能生效也不能用 —— fcitx5 画的是直角边框，和 9-patch 的圆角对不上。
- **面板背景图用 `themes/gen-panel.sh` 生成**，不要手改。尺寸/圆角/边框颜色都是
  脚本顶部的参数，两个主题一起重生。两个坑已写进脚本注释：不能用 `-stroke`
  画 1px 边框（抗锯齿会把不透明度摊到 67%，边框发虚），降采样必须用 `-filter Box`
  （Lanczos 会振铃，颜色偏）。`Background/Margin` 必须 >= 圆角半径，否则拉伸区切进圆角。
- **微信面板的边界感主要靠投影，不是边框**。拿微信输入法截图逐像素量过：
  白底 `#ffffff` 上只有 1px `#dadada` 描边，外侧另有一层约 15px 的投影
  （`#fbfbfb` → `#efefef`，越近面板越深）。只抄那条 `#dadada` 会觉得“几乎看不到边框”，
  要得到同样的轮廓感得把阴影也烘进 PNG（靠四周透明边 + 同比例抬高 `Background/Margin`）。
- 主题未声明 `[AccentColorField]` 时，`UseAccentColor=True` 不会覆盖主题颜色。

## 本目录之外的相关配置

- `wm/hypr/hyprland.conf` 里有 `exec-once = fcitx5 -d`（Hyprland 自己的自启，不走 XDG autostart）。
- `submodule/tui-bridge/linux/im.c` 通过 DBus 调 `org.fcitx.Fcitx.Rime1` 切 rime 的 ascii_mode，
  供 Neovim 用；改 rime 方案时注意别动 `ascii_mode` 开关的语义。
