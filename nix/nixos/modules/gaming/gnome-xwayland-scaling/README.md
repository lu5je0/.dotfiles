# GNOME 游戏缩放

`nixos/modules/gaming.nix` 通过导入本目录的 NixOS 模块启用：

```nix
imports = [ ./gaming/gnome-xwayland-scaling ];
```

`default.nix` 统一定义 Mutter 与 `gnome-settings-daemon` 的覆盖以及 dconf 默认值。
覆盖在主机覆盖之后应用，两个包均追加到原有补丁列表，保留主机专用修复及补丁顺序。
补丁和隔离测试也放在本目录，没有额外的启用选项。

## XWayland 原生分辨率

`xwayland-native-resolution.patch` 添加
`org.gnome.mutter.wayland xwayland-native-resolution` 布尔设置，上游默认行为为 `false`，
游戏模块的 dconf 默认值为 `true`。仅在 logical 布局、单个 logical monitor、
`xwayland-scaling-factor=0`（自动）时使用显示器实际缩放比例。
多屏及手动缩放因子保留上游规则。此设置影响整个 XWayland 实例中的 X11 应用。

补丁让 X11 坐标、窗口尺寸、纹理、damage 和输入区域使用同一个小数缩放因子。
XSettings 的 UI 缩放和原生 Wayland 客户端的 buffer scale 仍为整数。
例如单屏 3840×2160、166.7% 缩放时，XWayland 的当前尺寸为 3840×2160。

`xwayland-content-scale.patch` 通过 `org.gnome.Mutter.X11.ContentScalingFactor`
发布实际内容比例。配套的设置守护进程补丁使用它同时计算 XResources 和 XSettings，
保留 GNOME 的文字缩放比例。GTK 窗口比例采用实际内容比例的整数部分（最小为 1），
`Gdk/UnscaledDPI` 表达剩余的小数比例，采用
[KDE 的窗口比例和 DPI 分解方式](https://github.com/KDE/kde-gtk-config/blob/master/kded/gtkconfig.cpp#L300)。
例如文字缩放为 1 时，166.7% 对应 `Gdk/WindowScalingFactor=1`、
`Gdk/UnscaledDPI=160*1024`；`Xft/DPI` 和 XResources `Xft.dpi` 同样对应 160 DPI。
与 KDE 移除 `Xft/DPI`、另写 GTK 配置文件的做法不同，这里继续通过 GSD 发布一致的
绝对 DPI，以兼容 GTK2 和直接读取 XSettings 的应用。光标大小按实际内容比例取整，
默认 24 在 166.7% 下对应 40 像素，不随文字缩放变化。
传统 GTK 的控件仍受整数窗口比例限制，这不会让所有 X11 工具包的界面大小自动一致。
SDL 探针不能作为 Steam 主界面缩放正确的验证；Steam 需要恢复其 UI 缩放到 100%，
完全退出后重开，再检查 Chromium 界面的显示比例和实际清晰度。
缺少新 D-Bus 属性时，设置守护进程回退到整数 UI 比例。

更改后重新登录。临时关闭：

```sh
gsettings set org.gnome.mutter.wayland xwayland-native-resolution false
```

恢复模块默认值：

```sh
gsettings reset org.gnome.mutter.wayland xwayland-native-resolution
```

桌面内关闭开关不能卸载补丁。完全回退时，移除 `gaming.nix` 中本模块的 import，
再重建系统并重新登录。

## 验证

单独构建 Mutter：

```sh
nix build --no-link --print-out-paths path:.#nixosConfigurations.huskar.pkgs.mutter
```

`smoke-test.py` 接受上面输出的包路径；PATH 需要包含 Python 3、`dbus-run-session`、
`gsettings`、`xrandr`、`glxgears`（mesa-demos）和 `xwininfo`：

```sh
python nix/nixos/modules/gaming/gnome-xwayland-scaling/smoke-test.py /nix/store/…-mutter-50.5
```

脚本在独立 D-Bus、运行时目录和 GSettings 配置中启动 headless Mutter，需要可用的
EGL render node，不替换当前桌面。它检查开关前后的 XWayland 尺寸、100% 至 250%
缩放下的实际 GLX 全屏窗口、手动缩放覆盖、混合缩放双屏和单屏恢复。
加入 `--settings-daemon`、`--x11-library`、`--sdl-library` 并在 PATH 中提供 `xrdb`，
可同时检查实际 DPI、文字缩放、SDL 的内容比例，以及 GTK XSettings 和光标大小。
三个参数依次接受对应包目录、libX11.so.6 和 libSDL3.so.0 路径，动态库需为宿主架构：

```sh
python nix/nixos/modules/gaming/gnome-xwayland-scaling/smoke-test.py /nix/store/…-mutter-50.5 \
  --settings-daemon /nix/store/…-gnome-settings-daemon-50.1 \
  --x11-library /nix/store/…-libx11-…/lib/libX11.so.6 \
  --sdl-library /nix/store/…-sdl3-…-lib/lib/libSDL3.so.0
```

追加 `--gtk-library /nix/store/…-gtk+3-…/lib/libgtk-3.so.0` 可实际初始化 GTK3 的
X11 后端，读取监视器整数比例与字体 DPI，检查 Chromium GTK3 路径所需的组合比例。
该检查不运行 Steam 或 Chromium 本身。

验证无 `ContentScalingFactor` 属性的旧 Mutter 时，添加 `--legacy-content-scale`，
检查设置守护进程是否回退到整数 DPI。

脚本不检查实际游戏的图像清晰度、鼠标锁定、拖放或热插拔时已有窗口的连续性；
这些需要在重新登录后的桌面中验证。

构建完整系统并准备切换：

```sh
nix build --no-link path:.#nixosConfigurations.huskar.config.system.build.toplevel
sudo nixos-rebuild switch --flake path:.#huskar
```

补丁新增文件尚未被 Git 跟踪时使用 `path:.`，使 Nix 能读取该文件。
