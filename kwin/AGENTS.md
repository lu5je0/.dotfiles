# KWin TileWindow Script

KDE Wayland 下的窗口管理脚本，等同于 Windows 下的 AHK 窗口管理功能。

## 重载脚本

修改 `contents/code/main.js` 或 `wm/layout.jsonc` 后执行（会同步布局配置到 kwinrc 并重载脚本）：

```bash
bash ~/.dotfiles/kwin/reload.sh
```

reload.sh 做的事：`wm/layout.jsonc` 同步进 kwinrc `[Script-tilewindow]` 的 `wm_layout_json` →
`kpackagetool6 --upgrade` → qdbus 卸载/加载/启动脚本 → 启用插件。

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| Ctrl+Meta+H | 贴左半屏（自动交换占位窗口） |
| Ctrl+Meta+L | 贴右半屏（同上） |
| Ctrl+Meta+I | center_i 布局（大） |
| Ctrl+Meta+J | center_j 布局（小） |
| Ctrl+Meta+K | 最大化 |
| Alt+M | 最小化当前窗口 |
| Ctrl+Meta+T | 切换置顶 |
| Ctrl+Meta+W | 输出窗口信息到 journal |
| Ctrl+Meta+N/P | 循环切换下一个/上一个虚拟桌面 |
| Ctrl+Meta+Shift+N/P | 将当前窗口移到下一个/上一个虚拟桌面并跟随（循环） |
| Ctrl+Meta+Left/Right | 循环切换左右虚拟桌面 |

## 布局配置（wm/layout.jsonc）

hammerspoon/kwin/gnome 共用的统一配置（JSONC，支持 `//` 与 `/* */` 注释）。kwin 脚本无文件 IO 能力（QJSEngine 只暴露
readConfig/callDBus 等，没有 XMLHttpRequest/readFile），所以由 `reload.sh` 把
`wm/layout.jsonc` 剥注释后整段同步进 kwinrc `[Script-tilewindow]` 的 `wm_layout_json` key，
脚本每次按键通过 `readConfig` 读取并解析。改配置后需跑一次 `reload.sh`。

`rules` 为有序数组，每条规则由 `wm` / `app` / `screen` 三个可选字段 + `size` 组成：

```json
{
    "rules": [
        { "wm": ["kwin", "gnome"], "app": "kitty", "size": { "center_j": { "w": 1113, "h": 945 } } },
        { "size": { "center_i": { "w": { "ratio": 0.6875 } } } }
    ],
    "side": { "width": 1139, "height": 1218 }
}
```

- 匹配：从前往后取第一条「字段全匹配且 size 提供该 mode」的规则；字段缺省即通配，
  最后一条无字段规则是全局 fallback
- `wm` / `app` 可为字符串或数组；本端 `wm` 固定为 `kwin`、`screen` 固定为 `default`，
  app 匹配用 `resourceClass`（小写）
- 尺寸：`w/h` 为数字（绝对像素）或 `{ratio, offset}`（`max*ratio+offset`）；
  可选 `x/y` 为 `{align, offset}`（align: left/center/right/top/bottom，缺省 center），
  不写 `x/y` 时自动居中；坐标相对 workArea（已排除任务栏）
- `side` 给左右贴边用
- `main.js` 里的 `layoutConfig` 仅作读不到文件时的内置兜底
