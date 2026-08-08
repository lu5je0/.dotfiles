# GNOME TileWindow Extension

GNOME Shell 下的窗口管理扩展，是 `kwin/tilewindow` 的移植，逻辑保持一致（含 `layoutConfig` 的 kitty 专属尺寸）。

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

## 注意

- `layoutConfig` 改动需与 `kwin/tilewindow/contents/code/main.js` 保持同步
- 匹配 key 用 `get_wm_class()` 小写（kwin 侧是 `resourceClass`）
- mutter-18 的 `maximize()/unmaximize()` 无参数（旧版 MaximizeFlags 已移除）
