#!/usr/bin/env bash
set -euo pipefail

case "${1:-help}" in
  apply)
    shift
    exec "$(dirname "$(readlink -f "$0")")/window-decorations-setup" "$@"
    ;;
  apps)
    exec gjs -c '
      const Gio = imports.gi.Gio;
      const response = Gio.DBus.session.call_sync("org.gnome.Shell",
        "/org/gnome/Shell/Extensions/WindowDecorations",
        "org.gnome.Shell.Extensions.WindowDecorations", "ListApps", null,
        null, Gio.DBusCallFlags.NONE, 5000, null);
      const windows = JSON.parse(response.deep_unpack()[0]);
      for (const window of windows)
        print(`${window.title}\n  ${window.identifiers.join(", ")}`);
    '
    ;;
  help|--help|-h)
    cat <<'USAGE'
用法：
  window-decorations apply [config.json]  链接配置并启用扩展
  window-decorations apps                 列出当前窗口可匹配的应用标识

默认配置：~/.dotfiles/gnome/window-decorations/config.json
规则保存后自动生效；安装或升级扩展代码后需注销 GNOME 再登录。
USAGE
    ;;
  *) printf '未知命令：%s\n' "$1" >&2; exit 2 ;;
esac
