#!/usr/bin/env bash
set -euo pipefail

# 安装：nix profile add path:~/.dotfiles#window-decorations
# 配置：window-decorations-setup [config.json]；首次加载代码后注销重新登录。
uuid='smooth-shell-corners@xks'
previous_uuid='rounded-window-corners-next@khangphan90.github.io'
extension_dir='@extensionDir@'
schema='org.gnome.shell.extensions.smooth-shell-corners'
destination="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$uuid"
config_source="${1:-$HOME/.dotfiles/gnome/window-decorations/config.json}"
config_destination="${XDG_CONFIG_HOME:-$HOME/.config}/gnome-window-decorations/config.json"

if [[ $# -gt 1 || ! -f "$config_source" ]]; then
  printf '用法：window-decorations-setup [config.json]\n配置文件不存在：%s\n' "$config_source" >&2
  exit 1
fi
config_source=$(realpath "$config_source")
# 验证规则，并给仍加载着旧代码的会话保留白名单，避免临时影响所有应用。
whitelist=$(gjs -m "$extension_dir/tools/config-apps.js" "$config_source")
if [[ -e "$config_destination" && ! -L "$config_destination" ]]; then
  printf '已有手动配置，未覆盖：%s\n' "$config_destination" >&2
  exit 1
fi
mkdir -p "$(dirname "$config_destination")"
ln -sfn "$config_source" "$config_destination"

if [[ -e "$destination" && ! -L "$destination" ]]; then
  printf '已有手动安装的扩展，未覆盖：%s\n' "$destination" >&2
  exit 1
fi
mkdir -p "$(dirname "$destination")"
ln -sfn "$extension_dir" "$destination"

settings() {
  gsettings --schemadir "$extension_dir/schemas" "$@"
}

# 应用选择与装饰参数以 JSON 规则为准；上游设置只提供稳定的阴影预设。
settings set "$schema" whitelist-mode true
settings set "$schema" blacklist "$whitelist"
settings set "$schema" remove-native-radius false
settings set "$schema" fill-padding false
for side in top bottom left right; do
  settings set "$schema" "padding-$side" 0
done
settings set "$schema" border-width 0
settings set "$schema" keep-rounded-maximized false
settings set "$schema" keep-rounded-fullscreen false
settings set "$schema" custom-shadow true
settings set "$schema" shadow-strength 100
settings set "$schema" shadow-advanced false
settings set "$schema" keep-shadow-maximized false

# 旧扩展的 GLSLEffect 会在分数缩放下重复采样窗口，必须停用以免叠加。
gnome-extensions disable "$previous_uuid" 2>/dev/null || true

# 新扩展尚未被本次会话发现时，enable 命令无法处理；先保存下次登录的启用列表。
gjs -c '
  const Gio = imports.gi.Gio;
  const settings = new Gio.Settings({schema_id: "org.gnome.shell"});
  const uuid = ARGV[0];
  const previous = ARGV[1];
  const enabled = settings.get_strv("enabled-extensions").filter(value => value !== previous);
  if (!enabled.includes(uuid))
    enabled.push(uuid);
  settings.set_strv("enabled-extensions", enabled);
  const disabled = settings.get_strv("disabled-extensions");
  if (disabled.includes(uuid))
    settings.set_strv("disabled-extensions", disabled.filter(value => value !== uuid));
  Gio.Settings.sync();
' "$uuid" "$previous_uuid"

if gnome-extensions enable "$uuid" 2>/dev/null; then
  printf '扩展已启用，应用规则：%s\n首次更新代码需注销登录；之后修改 JSON 自动生效。\n' "$config_source"
else
  printf '扩展与配置已安装；请注销 GNOME 并重新登录以加载圆角和阴影。\n'
fi
