{ pkgs, flake }:

# mark-shot 不装进系统配置，作为独立 flake 供 `nix profile install ~/.dotfiles/nix/pkgs/mark-shot` 使用
flake.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
  # 补丁：托盘默认向宿主发 -symbolic 图标名、启动时把图标链到 ~/.local/share/icons（宿主只搜系统/用户图标目录）、
  # 自启动 desktop 写成 PATH 形式；见 gnome/AGENTS.md
  patches = (old.patches or [ ]) ++ [ ./mark-shot-tray-symbolic.patch ];
  postInstall = (old.postInstall or "") + ''
    install -Dm644 ${./mark-shot-symbolic.svg} \
      $out/share/icons/hicolor/symbolic/apps/mark-shot-symbolic.svg
  '';
  # 内有组件要读 GTK3 的 org.gtk.Settings.FileChooser，schema 不在运行环境里时进程启动即 abort
  # （GNOME 模块只把 GNOME 包集的 gsettings-schemas 注入 XDG_DATA_DIRS，不含 gtk3）
  # 托盘图标对宿主（gnome-shell）的可见性由补丁在启动时处理：链到 ~/.local/share/icons
  qtWrapperArgs = (old.qtWrapperArgs or [ ]) ++ [
    "--prefix XDG_DATA_DIRS : ${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
  ];
})
