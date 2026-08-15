#!/bin/bash
# 输入法安装：fcitx5(Linux) / Squirrel(macOS) + Rime 方案 + Linux 桌面侧集成
set -e

IME_DIR="$(cd "$(dirname "$0")" && pwd)"
RIME_SRC="$IME_DIR/rime"        # 仓库里的个人定制
RIME_ICE_URL="https://github.com/iDvel/rime-ice.git"

# -------------------------------------------------------------------- 依赖检查（Linux）
# 只查两个硬依赖，缺任何一个输入法都起不来。
# 查文件而不查包：不绑定发行版，且“文件在不在”比“包装没装”更贴近能不能用。
# 不阻断安装：建链接本身无害，装完包重跑一次就行。
MISSING_DEPS=()

check_linux_deps() {
  [[ "$(uname)" == "Linux" ]] || return 0

  # fcitx5 本体
  command -v fcitx5 >/dev/null || MISSING_DEPS+=("fcitx5:输入法框架本体")

  # Rime 引擎插件。拿 addon 描述文件探测，librime.so 的路径带架构名不好写。
  local found=""
  for d in /usr/share/fcitx5/addon /usr/local/share/fcitx5/addon; do
    [ -f "$d/rime.conf" ] && found=1 && break
  done
  [ -n "$found" ] || MISSING_DEPS+=("fcitx5-rime:fcitx5 的 Rime 引擎插件")

  if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
    return 0
  fi

  {
    echo
    echo "warn: 缺少 ${#MISSING_DEPS[@]} 个依赖"
    local entry
    for entry in "${MISSING_DEPS[@]}"; do
      printf '  %-14s %s\n' "${entry%%:*}" "${entry#*:}"
    done
    echo
    echo "  Debian/Ubuntu: sudo apt install ${MISSING_DEPS[*]%%:*}"
    echo
  } >&2
}

check_linux_deps

# ---------------------------------------------------------------- Rime 用户目录
# Rime 会在同一目录写 build/、installation.yaml、user.yaml 等运行时数据，
# 所以只能逐文件 link，不能整目录 link。
if [[ "$(uname)" == "Darwin" ]]; then
  RIME_DIR="${HOME}/Library/Rime"
else
  RIME_DIR="${HOME}/.local/share/fcitx5/rime"
fi

mkdir -p "$RIME_DIR"

# ------------------------------------------------------------------ 上游 rime-ice
# 不再当 dotfiles 的 submodule（它的历史很重，完整 clone 的 .git 有 230M+），
# 而是安装时**浅克隆**到 Rime 用户目录里 —— 它属于运行时数据，不是你的配置。
# 好处：仓库里不嵌外来 git 仓，`git clean -xdf` 也不会误删它。
RIME_ICE="$RIME_DIR/rime-ice"

if [ -f "$RIME_ICE/default.yaml" ]; then
  echo "rime-ice: 已存在 ($(git -C "$RIME_ICE" log -1 --format=%h 2>/dev/null || echo '非 git 仓'))"
elif [ -e "$RIME_ICE" ]; then
  # 不自动删 —— 里面可能有你自己放的东西
  echo "error: $RIME_ICE 已存在但不完整（没有 default.yaml）。确认内容后删掉重跑" >&2
  exit 1
else
  echo "rime-ice: 浅克隆 -> $RIME_ICE"
  git clone --depth 1 "$RIME_ICE_URL" "$RIME_ICE"
fi

# 上游 rime-ice 的方案文件与词库
# rime-ice 就在 RIME_DIR 里面，所以用相对链接，整个目录搬走也不会断
for f in "$RIME_ICE"/*.yaml "$RIME_ICE"/*.txt; do
  [ -f "$f" ] && ln -sf "rime-ice/$(basename "$f")" "$RIME_DIR/$(basename "$f")"
done
for d in cn_dicts en_dicts lua opencc; do
  [ -d "$RIME_ICE/$d" ] && ln -sfn "rime-ice/$d" "$RIME_DIR/$d"
done

# 个人定制（覆盖上游）：*.custom.yaml / custom_phrase.txt / *.lua
# 这些指回仓库，所以用绝对路径。
# *.lua 必须包含：rime_ice.custom.yaml 里 patch 了 lua_processor@ctrl_b_passthrough，
# 缺了对应 lua 文件 Rime 加载方案直接失败。
for f in "$RIME_SRC"/*.custom.yaml "$RIME_SRC"/custom_phrase.txt "$RIME_SRC"/*.lua; do
  [ -f "$f" ] && ln -sf "$f" "$RIME_DIR/"
done

echo "rime: linked to $RIME_DIR"

if [[ "$(uname)" == "Darwin" ]]; then
  echo "run 'Squirrel/Redeploy' from menu bar to apply"
  exit 0
fi

# ------------------------------------------------------------- fcitx5 候选框主题
# 主题读的是 data 目录（~/.local/share/fcitx5/themes），不是 ~/.config/fcitx5。
# 自带主题而不引用外部安装的：classicui.conf 里指一个本机没装的主题时，
# fcitx5 会静默退回内置样式，表现为「皮肤很奇怪」且没有任何报错。
FCITX5_THEME_DIR="${HOME}/.local/share/fcitx5/themes"
mkdir -p "$FCITX5_THEME_DIR"
for d in "$IME_DIR/themes"/*/; do
  [ -d "$d" ] || continue
  ln -sfn "${d%/}" "$FCITX5_THEME_DIR/$(basename "${d%/}")"
  echo "theme: $(basename "${d%/}")"
done

# ------------------------------------------------------- fcitx5 配置（Linux 独占）
# 这个目录只有 fcitx5 在用，且 fcitx5 保存设置时用 temp+rename 会冲掉文件级软链接，
# 所以整目录 link —— 这样在设置界面改的东西会直接落回仓库。
ln -sfn "$IME_DIR/fcitx5" "${HOME}/.config/fcitx5"
echo "fcitx5: ~/.config/fcitx5 -> ime/fcitx5"

# --------------------------------------------------- 桌面集成（共享目录，单文件 link）
# environment.d / autostart 是多个程序共用的 XDG 目录，
# 不整目录 link，只放我们自己的文件进去。
link_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  ln -sf "$src" "$dst"
  echo "linked: ~${dst#"$HOME"}"
}

# 输入法环境变量（Debian im-config 在 Wayland 下不会设置，详见该文件注释）
for f in "$IME_DIR/environment.d"/*.conf; do
  [ -f "$f" ] && link_file "$f" "${HOME}/.config/environment.d/$(basename "$f")"
done

# fcitx5 自启（同样因为 im-config 在 Wayland 下退化成空操作）
for f in "$IME_DIR/autostart"/*.desktop; do
  [ -f "$f" ] && link_file "$f" "${HOME}/.config/autostart/$(basename "$f")"
done

# ---------------------------------------------- 候选框 emoji 字体回退（fontconfig）
# 打出 🛏(U+1F6CF) 等 emoji 时被黑白的 Noto Sans Symbols 2 截胡、渲染成宽扁字形
# 撑大候选框。原因与做法详见 fontconfig/75-noto-emoji-over-symbols2.conf 顶部注释。
# conf.d 是共享 XDG 目录，只放这一个文件（单文件 link）；scan 规则要 fc-cache -f 才生效。
for f in "$IME_DIR/fontconfig"/*.conf; do
  [ -f "$f" ] && link_file "$f" "${HOME}/.config/fontconfig/conf.d/$(basename "$f")"
done
if command -v fc-cache >/dev/null; then
  fc-cache -f >/dev/null
  winner="$(fc-match -s "Noto Sans:charset=1f6cf" family 2>/dev/null | head -1)"
  echo "fontconfig: fc-cache rebuilt, U+1F6CF -> ${winner:-?}"
  case "$winner" in
    *"Color Emoji"*) : ;;
    *) echo "warn: emoji 回退仍未指向 Color Emoji，字体版本可能变化，需重算码点集" >&2 ;;
  esac
fi

# ------------------------------------------------- Chromium 系应用的 Wayland 输入法
# 本脚本**不管** ~/.local/share/applications/ 下的 desktop 覆盖（qoder.desktop 等）。
# 以前这里会从系统 desktop 生成一份并追加 flag，但那意味着每次重跑都会
# 覆盖掉手改内容，太容易误删东西，所以改成完全不碰。
#
# Chromium/Electron 在 Wayland 原生模式下不读 GTK_IM_MODULE/XMODIFIERS，走的是 Wayland
# text-input 协议，必须在 desktop 的 Exec 上手动加：
#   --enable-wayland-ime --wayland-text-input-version=3
# （KWin 只实现 text_input v2/v3，Chromium 默认 v1，所以版本必须指定；
#   这些开关也传不进环境变量或 VS Code 系的 argv.json）
# 做法：把 /usr/share/applications/<app>.desktop 拷到 ~/.local/share/applications/
# 后自己改 Exec。详见 ime/AGENTS.md。

# ---------------------------------------------------------------- KWin input method
# 上面的 flag 只是必要条件。Chromium 的 text-input 请求要由合成器中转,
# KWin 没配置 input method 时 org.kde.kwin.VirtualKeyboard 的 available 为 false,
# 整条通路是断的（Qt/GTK 应用不受影响，它们靠 *_IM_MODULE 直连 fcitx5 的 D-Bus）。
# fcitx5-wayland-launcher 不会另起一个 fcitx5，它只是把 KWin 给的 socket 通过
# OpenWaylandConnectionSocket 交给现有实例，和 autostart 不冲突。
# 注意：KWin 只在启动时读这个键，改完要重新登录。
KWIN_IM_LAUNCHER=/usr/share/applications/fcitx5-wayland-launcher.desktop
if command -v kwriteconfig6 >/dev/null && [ -f "$KWIN_IM_LAUNCHER" ]; then
  kwriteconfig6 --file kwinrc --group Wayland --key InputMethod "$KWIN_IM_LAUNCHER" 2>/dev/null
  echo "kwin: [Wayland] InputMethod -> fcitx5-wayland-launcher (需重新登录生效)"
fi

echo "run 'fcitx5 -r' or re-login to apply"

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
  echo "warn: 上面列的 ${#MISSING_DEPS[@]} 个依赖还没装，装完重跑本脚本" >&2
fi
