#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
检查 lazy.nvim 插件更新时间

用法:
  check-nvim-plugin-updates.sh [选项]

选项:
  --lock FILE     lazy-lock.json 路径 (默认: vim/lazy-lock.json)
  --lazy-dir DIR  插件目录 (默认: $XDG_DATA_HOME/nvim/lazy 或 ~/.local/share/nvim/lazy)
  --fetch         先 fetch 远程，再输出远程默认分支最新提交时间
  --json          以 JSON Lines 输出
  -h, --help      显示帮助
USAGE
}

LOCK_FILE="vim/lazy-lock.json"
if [[ -n "${XDG_DATA_HOME:-}" ]]; then
  LAZY_DIR_DEFAULT="${XDG_DATA_HOME}/nvim/lazy"
else
  LAZY_DIR_DEFAULT="$HOME/.local/share/nvim/lazy"
fi
LAZY_DIR="$LAZY_DIR_DEFAULT"
DO_FETCH=0
AS_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock)
      LOCK_FILE="$2"
      shift 2
      ;;
    --lazy-dir)
      LAZY_DIR="$2"
      shift 2
      ;;
    --fetch)
      DO_FETCH=1
      shift
      ;;
    --json)
      AS_JSON=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "需要 jq: 请先安装 jq" >&2
  exit 1
fi

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "找不到 lock 文件: $LOCK_FILE" >&2
  exit 1
fi

if [[ ! -d "$LAZY_DIR" ]]; then
  echo "找不到 lazy 插件目录: $LAZY_DIR" >&2
  exit 1
fi

format_row() {
  local plugin="$1"
  local status="$2"
  local lock_commit="$3"
  local local_commit="$4"
  local local_age="$5"
  local remote_commit="$6"
  local remote_age="$7"
  local behind="$8"

  if [[ "$AS_JSON" -eq 1 ]]; then
    jq -cn \
      --arg plugin "$plugin" \
      --arg status "$status" \
      --arg lock_commit "$lock_commit" \
      --arg local_commit "$local_commit" \
      --arg local_age "$local_age" \
      --arg remote_commit "$remote_commit" \
      --arg remote_age "$remote_age" \
      --arg behind "$behind" \
      '{plugin:$plugin,status:$status,lock_commit:$lock_commit,local_commit:$local_commit,local_age:$local_age,remote_commit:$remote_commit,remote_age:$remote_age,behind:($behind=="yes")}'
  else
    printf '%-28s %-14s %-12s %-22s' "$plugin" "$status" "$local_commit" "$local_age"
    if [[ "$DO_FETCH" -eq 1 ]]; then
      printf ' %-12s %-22s %-6s' "$remote_commit" "$remote_age" "$behind"
    fi
    printf '\n'
  fi
}

human_age_from_epoch() {
  local ts="$1"
  if [[ -z "$ts" || "$ts" == "-" ]]; then
    echo "-"
    return
  fi

  local now diff days months years rem_months day_unit month_unit year_unit
  now=$(date +%s)
  diff=$(( now - ts ))
  if (( diff < 0 )); then
    diff=0
  fi

  days=$(( diff / 86400 ))
  day_unit="days"
  if (( days == 1 )); then
    day_unit="day"
  fi
  if (( days < 30 )); then
    echo "${days} ${day_unit} ago"
    return
  fi

  months=$(( days / 30 ))
  month_unit="months"
  if (( months == 1 )); then
    month_unit="month"
  fi
  if (( months < 12 )); then
    echo "${months} ${month_unit} ago"
    return
  fi

  years=$(( months / 12 ))
  rem_months=$(( months % 12 ))
  year_unit="years"
  if (( years == 1 )); then
    year_unit="year"
  fi

  if (( rem_months == 0 )); then
    echo "${years} ${year_unit} ago"
  else
    month_unit="months"
    if (( rem_months == 1 )); then
      month_unit="month"
    fi
    echo "${years} ${year_unit} ${rem_months} ${month_unit} ago"
  fi
}

rows_tmp=$(mktemp)
trap 'rm -f "$rows_tmp"' EXIT

while IFS= read -r plugin; do
  lock_commit=$(jq -r --arg p "$plugin" '.[$p].commit // ""' "$LOCK_FILE")
  plugin_dir="$LAZY_DIR/$plugin"

  status="ok"
  local_commit="-"
  local_epoch=0
  local_age="-"
  remote_commit="-"
  remote_age="-"
  behind="-"

  if [[ ! -d "$plugin_dir/.git" ]]; then
    status="not_installed"
    row="$(format_row "$plugin" "$status" "$lock_commit" "$local_commit" "$local_age" "$remote_commit" "$remote_age" "$behind")"
    printf '%s\t%s\n' "$local_epoch" "$row" >> "$rows_tmp"
    continue
  fi

  local_commit=$(git -C "$plugin_dir" rev-parse --short=12 HEAD 2>/dev/null || echo "-")
  local_epoch=$(git -C "$plugin_dir" log -1 --format='%ct' 2>/dev/null || echo "0")
  local_age=$(human_age_from_epoch "$local_epoch")

  if [[ "$DO_FETCH" -eq 1 ]]; then
    if ! git -C "$plugin_dir" fetch --quiet --prune >/dev/null 2>&1; then
      status="fetch_failed"
    fi

    default_remote_ref=$(git -C "$plugin_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
    if [[ -n "$default_remote_ref" ]]; then
      remote_ref="$default_remote_ref"
    else
      # 回退到 lock 文件分支
      lock_branch=$(jq -r --arg p "$plugin" '.[$p].branch // ""' "$LOCK_FILE")
      if [[ -n "$lock_branch" ]]; then
        remote_ref="refs/remotes/origin/$lock_branch"
      else
        remote_ref=""
      fi
    fi

    if [[ -n "$remote_ref" ]] && git -C "$plugin_dir" rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
      remote_commit=$(git -C "$plugin_dir" rev-parse --short=12 "$remote_ref" 2>/dev/null || echo "-")
      remote_epoch=$(git -C "$plugin_dir" log -1 --format='%ct' "$remote_ref" 2>/dev/null || echo "-")
      remote_age=$(human_age_from_epoch "$remote_epoch")
      if [[ "$local_commit" != "$remote_commit" && "$local_commit" != "-" && "$remote_commit" != "-" ]]; then
        behind="yes"
      else
        behind="no"
      fi
    else
      if [[ "$status" == "ok" ]]; then
        status="no_remote_ref"
      fi
      behind="-"
    fi
  fi

  row="$(format_row "$plugin" "$status" "$lock_commit" "$local_commit" "$local_age" "$remote_commit" "$remote_age" "$behind")"
  printf '%s\t%s\n' "$local_epoch" "$row" >> "$rows_tmp"
done < <(jq -r 'keys[]' "$LOCK_FILE" | sort)

if [[ "$AS_JSON" -eq 0 ]]; then
  printf '%-28s %-14s %-12s %-22s' "PLUGIN" "STATUS" "LOCAL" "LOCAL_AGE"
  if [[ "$DO_FETCH" -eq 1 ]]; then
    printf ' %-12s %-22s %-6s' "REMOTE" "REMOTE_AGE" "BEHIND"
  fi
  printf '\n'
fi

sort -t $'\t' -k1,1n "$rows_tmp" | cut -f2-
