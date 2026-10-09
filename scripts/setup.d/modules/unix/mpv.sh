#!/bin/bash

REPO="git@github.com:lu5je0/mpv-lazy.git"
CLONE="$HOME/.local/share/mpv-lazy"
CONF="$CLONE/portable_config"
LINK="$HOME/.config/mpv"

# uosc 自带一个 Go 工具 ziggy，只做三件 Lua 做不到的事：读剪贴板（get-clipboard）、
# 向 OpenSubtitles 搜/下字幕（search-subtitles / download-subtitles）。它按
# ziggy-<platform> 找二进制（uosc main.lua），而 portable_config 里只有 ziggy-linux
# 和 ziggy-windows.exe —— 没有 ziggy-darwin，所以 macOS 上两个都用不到。
# 删掉当前平台不会执行的那个（macOS 上两个都删），每个平台省 5M+，不影响任何功能。
# 局限：ziggy-linux 是 x86-64，arm64 Linux 上同样跑不了（那三项功能本来就失效）。
prune_ziggy() {
  local dir="$CONF/scripts/uosc/bin" keep="" f base removed=0
  [ -d "$dir" ] || return 0
  case "$(uname -s)" in
    Darwin) keep="" ;;                 # 上游没有 ziggy-darwin
    Linux)  keep="ziggy-linux" ;;
    *)      keep="ziggy-windows.exe" ;;
  esac
  for f in "$dir"/ziggy-*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "$keep" ] && continue
    rm -f "$f" && removed=$((removed + 1))
  done
  [ "$removed" -gt 0 ] && echo "pruned: $removed unusable ziggy binary(ies) for $(uname -s)"
  return 0
}

linked=0
if [[ -L "$LINK" && "$(readlink "$LINK")" == "$CONF" ]]; then
  linked=1
elif [[ -d "$LINK" && ! -L "$LINK" && -z "$(ls -A "$LINK")" ]]; then
  # mpv 首次运行就会自己建 ~/.config/mpv 放 state（watch_later / shader cache）。
  # 空目录直接让位，否则任何跑过一次 mpv 的机器都装不上这个模块。
  rmdir "$LINK" && echo "note: removed empty $LINK (mpv auto-created it)"
elif [[ -e "$LINK" || -L "$LINK" ]]; then
  echo "error: $LINK exists and is not a symlink to $CONF"
  exit 1
fi

if [[ -d "$CLONE/.git" ]]; then
  echo "note: reuse existing clone at $CLONE (git pull to update)"
elif [[ -e "$CLONE" ]]; then
  echo "error: $CLONE exists but is not a git clone"
  exit 1
else
  mkdir -p "$(dirname "$CLONE")"
  # --no-cone: cone 模式会连带取出仓库根目录的 Windows 便携包（~110M）
  git clone --filter=blob:none --no-checkout "$REPO" "$CLONE" &&
    git -C "$CLONE" sparse-checkout set --no-cone '/portable_config/' &&
    git -C "$CLONE" checkout || exit 1
fi

# 每次都跑（不只是首次 clone），这样已有的安装也会被剪掉。
prune_ziggy

if [[ $linked == 1 ]]; then
  echo "skip: $LINK already linked"
else
  mkdir -p "$(dirname "$LINK")"
  ln -s "$CONF" "$LINK"
  echo "linked: $LINK -> $CONF"
fi
