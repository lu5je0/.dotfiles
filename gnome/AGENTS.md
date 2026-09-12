# GNOME TileWindow Extension

GNOME Shell 下的窗口管理扩展，是 `kwin/tilewindow` 的移植，逻辑保持一致。
窗口尺寸统一放在仓库根的 `wm/layout.jsonc`（hammerspoon/kwin/gnome 共用），每次按键实时读取。

目录即扩展本体：`tilewindow@lu5je0/`，通过 symlink 安装到
`~/.local/share/gnome-shell/extensions/tilewindow@lu5je0`（setup 模块 `gnome-tilewindow`）。

## 重载

修改 `extension.js` 后：

- Wayland 下必须**注销重登**（GNOME Wayland 不支持热重载 shell）
- 改了 `schemas/*.gschema.xml` 需先 `glib-compile-schemas tilewindow@lu5je0/schemas/`
- 启用：`gnome-extensions enable tilewindow@lu5je0`
- 看日志：`journalctl -f -o cat /usr/bin/gnome-shell`

## 快捷键

与 kwin 版一致：Ctrl+Super + H/L（贴边交换）、I/J（居中大/小）、K（最大化）、T（置顶）、W（窗口信息到 journal），Alt+M（最小化）。
Ctrl+Super+N/P 循环切换下一个/上一个工作区，Ctrl+Super+Shift+N/P 将当前窗口移到下一个/上一个工作区并跟随；Ctrl+Super+Left/Right 也循环切换左右工作区。切换由 workspace_manager 激活目标工作区，并复刻 `_showWorkspaceSwitcher` 的 WorkspaceSwitcherPopup 指示器；新版 gnome-shell 已移除 `Main.wm.actionMoveWorkspace*`。
动态工作区只有一个实际桌面时可进入末尾空白桌面以创建第二个；已有两个或更多实际桌面时，末尾空白占位桌面不参与快捷键循环。
快捷键定义在 gschema 里，可用 dconf 改（`/org/gnome/shell/extensions/tilewindow/`）。

## 布局配置（wm/layout.jsonc）

hammerspoon/kwin/gnome 共用的统一配置（JSONC，支持 `//` 与 `/* */` 注释），每次按键实时读取，改完立即生效，无需注销。
`rules` 为有序数组，每条规则由 `wm` / `app` / `screen` 三个可选字段 + `size` 组成：

```json
{
    "rules": [
        { "wm": "gnome", "app": "kitty", "size": { "center_j": { "w": 1113, "h": 950 } } },
        { "size": { "center_i": { "w": { "ratio": 0.6875 } } } }
    ],
    "side": { "width": 1139, "height": 1218 },
    "insets": {}
}
```

- 匹配：从前往后取第一条「字段全匹配且 size 提供该 mode」的规则；字段缺省即通配，
  最后一条无字段规则是全局 fallback
- `wm` / `app` 可为字符串或数组（数组 = 多端/多 app 共享一条规则）；本端 `wm` 固定为
  `gnome`、`screen` 固定为 `default`
- 尺寸：`w/h` 为数字（绝对像素）或 `{ratio, offset}`（`max*ratio+offset`）；
  可选 `x/y` 为 `{align, offset}`（align: left/center/right/top/bottom，缺省 center），
  不写 `x/y` 时自动居中
- `side` 给左右贴边用，放置与 kwin 一致（窗口居中在各自半屏内）；`width`/`height` 是上限，
  实际会夹到 workArea（宽 ≤ 半屏、高 ≤ workArea 高），否则固定像素值会压到顶栏和 dock 上
- `insets`（可选，`top`/`bottom`/`left`/`right`）在自动 dock 检测之后再手动扣一圈，
  一般不需要，仅用于自动检测失效或想额外留白的场景
- 内置 fallback 与 `kwin/tilewindow/contents/code/main.js` 的 `layoutConfig` 保持同步

## dock 排除

`getWorkArea()` 在 mutter workArea 基础上动态排除 dock，居中与左右贴边都生效：

- 从 `Main.layoutManager.uiGroup` 里找 name 为 `dashtodockContainer` 的 actor
- 用它的 `staticBox`（dash-to-dock 记录的「显示时」矩形，滑出隐藏时依然有效）与 workArea 求交
- 只裁 dock 贴的那一条边，边的方向由重叠区的细轴推断，所以 dock 换到任意一侧都自动跟随
- 固定 dock（`dock-fixed=true`）自带 struts，workArea 已排除它，交集为 0 不会重复裁；
  其他显示器上的 dock 同理不相交

## 注意

- 全屏窗口（游戏等）完全不碰：`getTargetWindow()` 在焦点窗口 `is_fullscreen()` 时直接返回 null，
  `listCandidates()` 也把它们排除，所以不会被当成 swap 对象推到另一边
- 匹配 key 用 `get_wm_class()` 小写（kwin 侧是 `resourceClass`）
- mutter-18 的 `maximize()/unmaximize()` 无参数（旧版 MaximizeFlags 已移除）
- Ctrl+Super+W 会把当前窗口几何、workArea 与检测到的 dock 矩形打到 journal，用于排查
- `bind()` 在每个快捷键处理函数跑完后调 `scheduleModifierResync()`，绕过 mutter 上游 bug
  （mutter#3636、#3672，50.4 仍未修）：mutter 抓走带修饰键的快捷键后，客户端可能收不到
  修饰键的 release，其修饰键状态卡住，表现为**悬停高亮正常但点击失效**（点击被当成
  Ctrl+点击），极易误判成「应用卡死」。用虚拟键盘补发一次 RELEASED 即可解除。
  必须轮询等到修饰键真正松开才补发，否则会打断按住 Ctrl+Super 连按 N/P 的连续切换；
  长按超过 3s 就放弃本次重同步。刻意不含 Super——卡住的 Super 在 GTK 侧无默认点击行为，
  而合成它的 release 会让 `overlay-key` 误弹 Overview

## mark-shot 托盘图标

GNOME 顶栏只对**按图标名拿到且以 `-symbolic` 结尾**的图标按前景色染色。mark-shot 上游的托盘逻辑是：主题名对宿主可见才发图标名，
否则退彩色位图；而它的可见性判断只认 `/usr/share` 等标准根目录，NixOS 的 profile 路径不算，所以上游默认走位图。
本仓库直接改默认行为（不再用 AppIndicator 扩展的 custom-icons 覆盖）。mark-shot 不装进系统配置，
作为根 flake 的 `packages.<system>.mark-shot` 装进用户 profile：`nix profile add path:~/.dotfiles#mark-shot`。

- `nix/pkgs/mark-shot/default.nix`：
  - `mark-shot-tray-symbolic.patch`：托盘优先发 `mark-shot-symbolic` 且宿主可见性判断扩展到会话的 `XDG_DATA_DIRS`；
    自启动 desktop 写成 `Exec=mark-shot --tray`（上游写 `applicationFilePath()`，Nix 下是 store 路径且绕过 wrapper，升级后会拉起旧版本）
  - SVG 装进包内 `share/icons/hicolor/symbolic/apps/`，应用启动（初始化托盘）时把它链到
    `~/.local/share/icons/hicolor/symbolic/apps/`——gnome-shell 解析图标名时看不清 nix profile（实测退占位符「…」），
    放用户目录则应用与宿主都能按名解析；该位置已有普通文件时不覆盖（可手动放文件迭代图标）
  - wrapper 补 gtk3 的 gsettings schema 目录（内有组件要读 `org.gtk.Settings.FileChooser`，缺失时进程启动即 abort）
- 上游包定义由根 flake 的 `mark-shot` input 提供（`github:jswysnemc/mark-shot`，nixpkgs follows 根），
  `nix/pkgs/mark-shot/` 目录不再自带 flake，只放补丁、SVG 与 `default.nix`

升级：仓库根 `nix flake update mark-shot` 后 `nix profile upgrade mark-shot`（profile 元素记录的是 `path:` URL，会取当前工作树）；
补丁可能要随上游 rebase（上游改了 `application_icon.{h,cpp}` / `windows_tray_controller.cpp` / `autostart_linux.cpp` 会打不上）。
迭代图标：改 `nix/pkgs/mark-shot/mark-shot-symbolic.svg` 后 upgrade（会重建包，应用下次启动重新链），重启 mark-shot 进程即可，不用重启扩展。
