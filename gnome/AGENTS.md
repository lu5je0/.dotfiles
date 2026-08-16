# GNOME TileWindow Extension

GNOME Shell 下的窗口管理扩展，是 `kwin/tilewindow` 的移植，逻辑保持一致。
窗口尺寸不再写死在代码里，而是放在 `tilewindow@lu5je0/layout.json`，每次按键实时读取。

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
另有 Ctrl+Super+Left/Right 切换左右工作区（等效系统 Ctrl+Alt+Left/Right：workspace_manager 激活相邻工作区，并复刻 `_showWorkspaceSwitcher` 的 WorkspaceSwitcherPopup 指示器；新版 gnome-shell 已移除 `Main.wm.actionMoveWorkspace*`）。
快捷键定义在 gschema 里，可用 dconf 改（`/org/gnome/shell/extensions/tilewindow/`）。

## layout.json

按 wmClass（小写）配置居中尺寸，`side` 配置左右贴边尺寸，示例见 `tilewindow@lu5je0/layout.json`：

```json
{
    "side": { "width": 1139, "height": 1218, "padding": 16 },
    "kitty": { "center_j": { "width": 1113, "height": 950 } }
}
```

- 每次按键实时读取，改完立即生效，无需注销
- 查找顺序：`<wmClass>` -> `default` -> 代码内置 fallback
- 条目只写 `width`/`height` 时自动居中，可选 `x`/`y` 指定相对 workArea 的偏移
- `side.padding`（可选，默认 0）：左右贴边时外侧与中间各留这么多空白，
  `side.width` 变成上限，超过 `(workArea.width - 3 * padding) / 2` 会被压下去，所以两边永不重叠
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
