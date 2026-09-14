#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
把 nix profile 的 .desktop 镜像到 GNOME 会实时监视的真实目录

背景:
  `nix profile install` 只替换 ~/.nix-profile 这个 symlink，新世代的
  share/applications 是另一个 inode。GLib 的 inotify 监视绑在旧世代的目录上，
  换 symlink 不产生任何事件，所以 GNOME 要重启 shell / 重新登录才看得到新应用。
  ~/.local/share/applications 是真实目录、又本来就在搜索路径最前面，往里面放
  symlink 会触发事件，图标立刻出现；symlink 指向 profile 路径，升级后自动跟随。
  参见 NixOS/nixpkgs#12757、#87668。

用法:
  sync-desktop-entries.sh [选项]

选项:
  --src DIR   源目录 (默认: ~/.nix-profile/share/applications)
  --dst DIR   目标目录 (默认: $XDG_DATA_HOME/applications 或 ~/.local/share/applications)
  --dry-run   只打印将要执行的操作
  -h, --help  显示帮助
USAGE
}

if [[ -n "${XDG_DATA_HOME:-}" ]]; then
  DST_DEFAULT="${XDG_DATA_HOME}/applications"
else
  DST_DEFAULT="$HOME/.local/share/applications"
fi
SRC="$HOME/.nix-profile/share/applications"
DST="$DST_DEFAULT"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src) SRC="$2"; shift 2 ;;
    --dst) DST="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# 去掉结尾斜杠：幂等判断比较的是 symlink 目标串，必须稳定
SRC="${SRC%/}"
DST="${DST%/}"

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '    [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

if [[ -L "$DST" ]]; then
  echo "错误: $DST 是 symlink，必须是真实目录（这正是本脚本要解决的问题）" >&2
  exit 1
fi

if [[ ! -d "$SRC" ]]; then
  echo "src 不存在，无事可做: $SRC"
  exit 0
fi

[[ "$DRY_RUN" -eq 1 ]] || mkdir -p "$DST"

echo "src: $SRC"
echo "dst: $DST"

added=0 updated=0 kept=0 pruned=0 unchanged=0

# 1) 清掉本脚本建过、但源文件已消失的悬空 symlink（包卸载 / 世代被 GC）
for l in "$DST"/*.desktop; do
  [[ -L "$l" ]] || continue
  case "$(readlink "$l")" in
    "$SRC"/*) ;;
    *) continue ;;
  esac
  [[ -e "$l" ]] && continue
  echo "  prune  $(basename "$l")"
  run rm -f "$l"
  pruned=$((pruned + 1))
done

# 2) 建立 / 刷新镜像。已存在的手工文件不覆盖（它在搜索路径里更靠前，是刻意的覆盖）
for f in "$SRC"/*.desktop; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"
  d="$DST/$base"
  want="$SRC/$base"

  if [[ -e "$d" && ! -L "$d" ]]; then
    echo "  keep   $base  (已有真实文件，未覆盖)"
    kept=$((kept + 1))
    continue
  fi
  if [[ -L "$d" && "$(readlink "$d")" == "$want" ]]; then
    unchanged=$((unchanged + 1))
    continue
  fi

  if [[ -L "$d" ]]; then
    echo "  update $base"
    updated=$((updated + 1))
  else
    echo "  add    $base"
    added=$((added + 1))
  fi
  run ln -sfn "$want" "$d"
done

echo
printf '完成: 新增 %d, 更新 %d, 跳过(手工文件) %d, 清理 %d, 已是最新 %d\n' \
  "$added" "$updated" "$kept" "$pruned" "$unchanged"
