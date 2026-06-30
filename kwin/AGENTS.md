# KWin TileWindow Script

KDE Wayland 下的窗口管理脚本，等同于 Windows 下的 AHK 窗口管理功能。

## 重载脚本

修改 `contents/code/main.js` 后，执行：

```bash
kpackagetool6 --type KWin/Script --upgrade ~/.dotfiles/kwin/tilewindow
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript tilewindow
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$HOME/.local/share/kwin/scripts/tilewindow/contents/code/main.js" tilewindow
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| Ctrl+Meta+H | 贴左半屏（自动交换占位窗口） |
| Ctrl+Meta+L | 贴右半屏（同上） |
| Ctrl+Meta+I | center_i 布局（大） |
| Ctrl+Meta+J | center_j 布局（小） |
| Ctrl+Meta+K | 最大化 |
| Ctrl+Meta+T | 切换置顶 |
| Ctrl+Meta+W | 输出窗口信息到 journal |

## layoutConfig

`main.js` 顶部的 `layoutConfig` 按 `resourceClass`（小写）配置每个应用的居中尺寸。layout 函数接收 workArea 的宽高（已排除任务栏），返回相对于 workArea 的坐标。
