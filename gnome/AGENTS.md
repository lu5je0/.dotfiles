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

与 kwin 版一致：Ctrl+Super + H/L（贴边交换）、I/J（居中大/小）、K（最大化）、T（置顶）、W（窗口信息到 journal）。
快捷键定义在 gschema 里，可用 dconf 改（`/org/gnome/shell/extensions/tilewindow/`）。

## layout.json

按 wmClass（小写）配置居中尺寸，`side` 配置左右贴边尺寸，示例见 `tilewindow@lu5je0/layout.json`：

```json
{
    "side": { "width": 1139, "height": 1218 },
    "kitty": { "center_j": { "width": 1113, "height": 950 } }
}
```

- 每次按键实时读取，改完立即生效，无需注销
- 查找顺序：`<wmClass>` -> `default` -> 代码内置 fallback
- 条目只写 `width`/`height` 时自动居中，可选 `x`/`y` 指定相对 workArea 的偏移
- `insets`（可选，`top`/`bottom`/`left`/`right`）从 mutter workArea 里再扣掉一圈：顶栏本身已由 struts 排除，
  但自动隐藏的 dash-to-dock（`dock-fixed=false`）不设 struts，需要用 `bottom` 手动预留其高度。
  对居中与左右贴边都生效
- 内置 fallback 与 `kwin/tilewindow/contents/code/main.js` 的 `layoutConfig` 保持同步

## 注意

- 匹配 key 用 `get_wm_class()` 小写（kwin 侧是 `resourceClass`）
- mutter-18 的 `maximize()/unmaximize()` 无参数（旧版 MaximizeFlags 已移除）
