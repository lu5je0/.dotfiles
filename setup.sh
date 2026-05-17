#!/bin/bash

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SETUP_DIR="$DOTFILES_DIR/scripts/setup.d"

if [[ "$(uname -a)" == *WSL* ]] && [[ "$DOTFILES_DIR" == /mnt/c/* ]]; then
  MODULE_DIR="$SETUP_DIR/modules/win"
  export WIN_HOME="${DOTFILES_DIR%/.dotfiles}"
else
  MODULE_DIR="$SETUP_DIR/modules/unix"
fi

export DOTFILES_DIR

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET="" C_BOLD="" C_DIM="" C_CYAN="" C_GREEN="" C_YELLOW="" C_RED=""
fi

line() {
  printf "%b\n" "${C_DIM}------------------------------------------------------------${C_RESET}"
}

title() {
  line
  printf "%b\n" "${C_BOLD}${C_CYAN}$1${C_RESET}"
  line
}

ok() { printf "%b\n" "${C_GREEN}[ OK ]${C_RESET} $1"; }
warn() { printf "%b\n" "${C_YELLOW}[WARN]${C_RESET} $1"; }
err() { printf "%b\n" "${C_RED}[FAIL]${C_RESET} $1"; }

if [ "$(uname)" = "Darwin" ]; then
  [[ ! -f "$HOME/.mac" ]] && touch "$HOME/.mac"
fi

# --- status check ---
check_module_status() {
  local check_path="$1" check_type="$2"
  check_path="${check_path/#\~/$HOME}"
  check_path="$(eval echo "$check_path")"
  if [[ ! -e "$check_path" ]]; then
    echo ""
    return
  fi
  if [[ "$check_type" == "exists" ]]; then
    echo "installed"
    return
  fi
  if [[ -L "$check_path" ]]; then
    local target dotfiles_real
    target="$(readlink -f "$check_path")"
    dotfiles_real="$(readlink -f "$DOTFILES_DIR")"
    if [[ "$target" == "$dotfiles_real"* ]]; then
      echo "installed"
    else
      echo "conflict"
    fi
  else
    echo "conflict"
  fi
}

# --- execute a LINK module ---
run_link_module() {
  local source="$1" target="$2"
  target="${target/#\~/$HOME}"
  target="$(eval echo "$target")"
  if [[ -e "$target" ]]; then
    echo "skip: $target exists"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  ln -s "$DOTFILES_DIR/$source" "$target"
}

# --- parse modules.conf ---
CONF_FILE="$MODULE_DIR/modules.conf"
if [[ ! -f "$CONF_FILE" ]]; then
  err "No modules.conf found in $MODULE_DIR"
  exit 1
fi

module_descs=()
module_types=()       # "link" or "script"
module_sources=()     # for link: relative path; for script: script path
module_targets=()     # for link: target path; for script: check path
module_check_types=() # "symlink" or "exists"
module_status=()
selections=()

cur_desc="" cur_link="" cur_script="" cur_check="" cur_check_exists=""

flush_module() {
  [[ -z "$cur_link" && -z "$cur_script" ]] && return
  if [[ -n "$cur_link" ]]; then
    local source="${cur_link%% -> *}"
    local target="${cur_link##* -> }"
    [[ -z "$cur_desc" ]] && cur_desc="link ./$source -> $target"
    module_descs+=("$cur_desc")
    module_types+=("link")
    module_sources+=("$source")
    module_targets+=("$target")
    module_check_types+=("symlink")
    module_status+=("$(check_module_status "$target" "symlink")")
    selections+=(0)
  elif [[ -n "$cur_script" ]]; then
    local script_path="$MODULE_DIR/$cur_script"
    local check_path="" check_type=""
    if [[ -n "$cur_check" ]]; then
      check_path="$cur_check"
      check_type="symlink"
    elif [[ -n "$cur_check_exists" ]]; then
      check_path="$cur_check_exists"
      check_type="exists"
    fi
    module_descs+=("$cur_desc")
    module_types+=("script")
    module_sources+=("$script_path")
    module_targets+=("$check_path")
    module_check_types+=("$check_type")
    module_status+=("$(check_module_status "$check_path" "$check_type")")
    selections+=(0)
  fi
  cur_desc="" cur_link="" cur_script="" cur_check="" cur_check_exists=""
}

while IFS= read -r conf_line; do
  [[ "$conf_line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${conf_line// }" ]] && continue

  if [[ "$conf_line" =~ ^\[.*\]$ ]]; then
    flush_module
  elif [[ "$conf_line" =~ ^desc[[:space:]]*=[[:space:]]*(.*) ]]; then
    cur_desc="${BASH_REMATCH[1]}"
  elif [[ "$conf_line" =~ ^link[[:space:]]*=[[:space:]]*(.*) ]]; then
    cur_link="${BASH_REMATCH[1]}"
  elif [[ "$conf_line" =~ ^script[[:space:]]*=[[:space:]]*(.*) ]]; then
    cur_script="${BASH_REMATCH[1]}"
  elif [[ "$conf_line" =~ ^check_exists[[:space:]]*=[[:space:]]*(.*) ]]; then
    cur_check_exists="${BASH_REMATCH[1]}"
  elif [[ "$conf_line" =~ ^check[[:space:]]*=[[:space:]]*(.*) ]]; then
    cur_check="${BASH_REMATCH[1]}"
  fi
done < "$CONF_FILE"
flush_module

total="${#module_descs[@]}"
if [ "$total" -eq 0 ]; then
  warn "No modules found. Exit."
  exit 1
fi

cursor=0

# --- count selected ---
count_selected() {
  local c=0
  for s in "${selections[@]}"; do
    (( s == 1 )) && (( c++ ))
  done
  echo "$c"
}

# --- refresh status for all modules ---
refresh_status() {
  for i in "${!module_types[@]}"; do
    [[ -z "${module_targets[$i]}" ]] && continue
    module_status[$i]="$(check_module_status "${module_targets[$i]}" "${module_check_types[$i]}")"
  done
}

# --- TUI ---
search_query=""
search_mode=0
filtered_indices=()

update_filter() {
  filtered_indices=()
  if [[ -z "$search_query" ]]; then
    for i in "${!module_descs[@]}"; do
      filtered_indices+=("$i")
    done
  else
    for i in "${!module_descs[@]}"; do
      if [[ "${module_descs[$i],,}" == *"${search_query,,}"* ]]; then
        filtered_indices+=("$i")
      fi
    done
  fi
}

render_menu() {
  printf "\033[2J\033[H"
  title "Dotfiles Setup"
  printf "%b\n" "Select modules to run  ${C_DIM}($(count_selected)/$total selected)${C_RESET}"
  printf "%b\n" "${C_DIM}j/k move, Space toggle, / search, Enter run, q quit${C_RESET}"
  echo
  local fi_total="${#filtered_indices[@]}"
  if [ "$fi_total" -eq 0 ]; then
    printf "%b\n" "  ${C_DIM}(no matches)${C_RESET}"
  else
    for fi_idx in "${!filtered_indices[@]}"; do
      local i="${filtered_indices[$fi_idx]}"
      marker="${C_DIM}[ ]${C_RESET}"
      if [ "${selections[$i]}" -eq 1 ]; then
        marker="${C_GREEN}[x]${C_RESET}"
      fi
      pointer="  "
      if [ "$fi_idx" -eq "$cursor" ]; then
        pointer="${C_BOLD}${C_CYAN}>${C_RESET} "
      fi
      status_badge=""
      if [[ "${module_status[$i]}" == "installed" ]]; then
        status_badge=" ${C_GREEN}(installed)${C_RESET}"
      elif [[ "${module_status[$i]}" == "conflict" ]]; then
        status_badge=" ${C_YELLOW}(conflict)${C_RESET}"
      fi

      if [ "$fi_idx" -eq "$cursor" ]; then
        printf "%b\n" "${pointer}${marker} ${C_BOLD}${module_descs[$i]}${C_RESET}${status_badge}"
      else
        printf "%b\n" "${pointer}${marker} ${module_descs[$i]}${status_badge}"
      fi
    done
  fi
  echo
  if (( search_mode )); then
    printf "%b" "${C_CYAN}> ${C_RESET}${search_query}"
  else
    line
  fi
}

read_key() {
  local k
  IFS= read -rsn1 k
  if [[ "$k" == $'\x1b' ]]; then
    IFS= read -rsn1 -t 0.01 k2
    if [[ "$k2" == "[" ]]; then
      IFS= read -rsn1 -t 0.01 k3
      echo "ESC[$k3"
      return
    fi
    echo "ESC"
    return
  fi
  echo "$k"
}

update_filter
render_menu
while :; do
  key="$(read_key)"
  fi_total="${#filtered_indices[@]}"

  if (( search_mode )); then
    case "$key" in
      ""|"ESC")
        # Exit search mode
        search_mode=0
        search_query=""
        update_filter
        cursor=0
        ;;
      $'\x7f'|$'\x08')
        # Backspace
        if [[ -n "$search_query" ]]; then
          search_query="${search_query%?}"
          update_filter
          fi_total="${#filtered_indices[@]}"
          if (( cursor >= fi_total )); then
            cursor=$(( fi_total > 0 ? fi_total - 1 : 0 ))
          fi
        fi
        ;;
      " ")
        if (( fi_total > 0 )); then
          real_idx="${filtered_indices[$cursor]}"
          if [ "${selections[$real_idx]}" -eq 1 ]; then
            selections[$real_idx]=0
          else
            selections[$real_idx]=1
          fi
        fi
        ;;
      "ESC[B")
        if (( fi_total > 0 )); then
          cursor=$(( (cursor + 1) % fi_total ))
        fi
        ;;
      "ESC[A")
        if (( fi_total > 0 )); then
          cursor=$(( (cursor - 1 + fi_total) % fi_total ))
        fi
        ;;
      *)
        if [[ ${#key} -eq 1 ]] && [[ "$key" =~ [[:print:]] ]]; then
          search_query+="$key"
          update_filter
          fi_total="${#filtered_indices[@]}"
          cursor=0
        fi
        ;;
    esac
  else
    case "$key" in
      "q") exit 0 ;;
      "") break ;;
      " ")
        if (( fi_total > 0 )); then
          real_idx="${filtered_indices[$cursor]}"
          if [ "${selections[$real_idx]}" -eq 1 ]; then
            selections[$real_idx]=0
          else
            selections[$real_idx]=1
          fi
        fi
        ;;
      "/")
        search_mode=1
        search_query=""
        cursor=0
        ;;
      "j"|"ESC[B")
        if (( fi_total > 0 )); then
          cursor=$(( (cursor + 1) % fi_total ))
        fi
        ;;
      "k"|"ESC[A")
        if (( fi_total > 0 )); then
          cursor=$(( (cursor - 1 + fi_total) % fi_total ))
        fi
        ;;
    esac
  fi
  render_menu
done

has_selected=0
for s in "${selections[@]}"; do
  (( s == 1 )) && has_selected=1 && break
done
if (( ! has_selected )); then
  warn "No modules selected. Exit."
  exit 1
fi

# --- execute ---
for i in "${!module_descs[@]}"; do
  if [ "${selections[$i]}" -ne 1 ]; then
    continue
  fi
  title "Running: ${module_descs[$i]}"
  if [[ "${module_types[$i]}" == "link" ]]; then
    run_link_module "${module_sources[$i]}" "${module_targets[$i]}"
    status=$?
  else
    bash "${module_sources[$i]}"
    status=$?
  fi
  if [ $status -eq 0 ]; then
    ok "done: ${module_descs[$i]}"
  else
    err "failed($status): ${module_descs[$i]}"
  fi
done

# refresh and show final status
refresh_status
echo
title "Final Status"
for i in "${!module_descs[@]}"; do
  if [ "${selections[$i]}" -ne 1 ]; then
    continue
  fi
  status_badge=""
  if [[ "${module_status[$i]}" == "installed" ]]; then
    status_badge="${C_GREEN}(installed)${C_RESET}"
  elif [[ "${module_status[$i]}" == "conflict" ]]; then
    status_badge="${C_YELLOW}(conflict)${C_RESET}"
  else
    status_badge="${C_RED}(not installed)${C_RESET}"
  fi
  printf "%b\n" "  ${module_descs[$i]} $status_badge"
done
