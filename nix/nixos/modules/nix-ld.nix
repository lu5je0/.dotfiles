{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # ── nixpkgs 默认集（显式列出便于查阅，重复声明无害）──
      acl
      attr
      bzip2
      curl
      libsodium
      libssh
      libxml2
      openssl
      stdenv.cc.cc.lib
      systemd
      util-linux
      xz
      zlib
      zstd

      # ── 补齐项：跑非 Nix 二进制（AppImage / 官方 tarball / 自编译）的实际依赖 ──
      alsa-lib # 音频后端（Electron / Qt / 游戏）
      at-spi2-core # libatk-1.0 / libatk-bridge-2.0 / libatspi.so.0，Electron/GTK 无障碍栈必需
      cairo
      cups # 打印对话框，WPS 等会 dlopen
      dbus
      expat
      fontconfig
      freetype
      gdk-pixbuf # GTK 应用图标加载
      glib
      gtk3 # Electron/GTK 前端
      icu # 文本处理，Chromium 系必需
      libdrm
      libgbm # libgbm.so.1，Chromium/Electron 的 GBM 后端；mesa 26 起从 mesa 拆出，须单独列
      libglvnd # libGL.so.1 分发层；硬件渲染仍需 /run/opengl-driver
      libnotify
      libpulseaudio
      libunwind
      libusb1
      libuuid
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxi
      libxkbcommon
      libxrandr
      libxrender
      libxscrnsaver # libXss.so.1，Chromium 系必需
      libxtst
      mesa # 软件渲染兜底（llvmpipe）
      nspr
      nss # Chromium/Electron 的 NSS
      pango
      pipewire
      vulkan-loader
      wayland
    ];
  };
}
