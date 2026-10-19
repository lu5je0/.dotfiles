# 按应用配置窗口圆角和阴影

扩展直接读取 `~/.dotfiles/nix/nixos/pkgs/window-decorations/config.json`，无需配置链接或初始化脚本。
扩展使用 Smooth Shell Corners 的分数缩放渲染器，
由本仓库的补丁添加应用规则和文件监听。保留应用自身的标题栏。

本目录集中维护包定义、补丁、规则、辅助命令、测试和 `module.nix` 中的 dconf 设置。
`nix/nixos/modules/gnome.nix` 只负责导入模块、安装并默认启用扩展，dconf 禁止扩展修改全局 GTK CSS。
首次安装：

```sh
sudo nixos-rebuild switch --flake ~/.dotfiles
```

注销 GNOME 并重新登录以加载代码。之后编辑 JSON 并保存，会自动更新已打开的窗口，
不需要重启应用、重新构建 Nix 包或运行 `nixos-rebuild switch`。
语法或字段错误会记录到 GNOME Shell 日志，并保留上一份有效规则。

`window-decorations apps` 列出当前窗口的应用标识，选择其中任意一个写进 `match`。
匹配忽略大小写和 `.desktop` 后缀，使用完整标识，不支持通配符。规则按顺序匹配，
第一条命中即生效；未匹配的应用不添加效果。

示例：

```json
{
  "defaults": {
    "radius": 8,
    "smoothing": 0.25,
    "shadowStrength": 100
  },
  "rules": [
    {"match": ["chatgpt", "codex"], "corners": true, "shadow": true},
    {"match": ["kitty"], "corners": false, "shadow": true, "shadowStrength": 70},
    {"match": ["org.mozilla.firefox"], "radius": 6, "shadow": false}
  ]
}
```

规则字段覆盖 `defaults`，未设置的字段使用下表的内置默认值：

| 字段 | 默认值 | 含义 |
| --- | --- | --- |
| `match` | 必填 | 一组应用标识，命中任意一个即可 |
| `enabled` | `true` | 关闭整条规则，仍阻止后续同应用规则生效 |
| `corners` | `true` | 是否开启圆角；关闭时仍可单独开启阴影 |
| `radius` | `8` | 逻辑像素半径，整数 `0`–`50`，`0` 表示直角 |
| `smoothing` | `0.25` | `0`–`1`；`0` 是圆弧，越大越接近平滑方圆角 |
| `shadow` | `true` | 是否开启扩展的阴影 |
| `shadowStrength` | `100` | 整数 `0`–`200`；`100` 为 GNOME 原生风格预设，`0` 关闭 |
| `maximized` | `false` | 最大化时是否继续添加装饰 |
| `fullscreen` | `false` | 全屏时是否继续添加装饰 |

两种效果都关闭的规则不会创建渲染效果。关闭扩展阴影不会移除应用自己绘制的阴影。
扩展不修改 GTK 的全局 CSS。菜单、工具提示及桌面图标窗口不处理。

## 性能

未匹配应用不会创建圆角渲染效果或离屏内容纹理，但仍有少量窗口事件监听和规则匹配的
CPU 开销。配置通过文件事件监听，不定时轮询。

匹配应用会多一个合成渲染步骤，以及按实际显示缩放密度分配的内容纹理。
例如 1200×800 逻辑像素窗口在 166.7% 缩放下，仅一份 RGBA8 内容纹理约需 10 MiB；
另有阴影纹理和 GPU 资源。共享阴影缓存有 16 MiB 上限，这不是整个扩展的显存上限。
窗口越多、越大或持续刷新，开销越明显，也可能间接与其他程序竞争 GPU 资源。
默认最大化和全屏窗口不添加效果。

更新代码后需要重新登录；可用 `gnome-extensions disable smooth-shell-corners@xks` 随时停用。

旧 profile 安装只需迁移一次：先安装系统版本，再删除
`~/.local/share/gnome-shell/extensions/smooth-shell-corners@xks` 的旧符号链接，
避免遮盖系统版本；然后运行 `nix profile remove codex-window-decorations`
（如果以新名字安装，则移除 `window-decorations`）。切换到新代码并重新登录后，
旧的 `~/.config/gnome-window-decorations/config.json` 配置链接可删除。
如果以前使用过 Rounded Window Corners Reborn，还需运行
`gnome-extensions disable rounded-window-corners-next@khangphan90.github.io`，避免两套效果叠加。
后续扩展代码随 `nixos-rebuild switch` 更新，不再通过用户 profile 管理。
