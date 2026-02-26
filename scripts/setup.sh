#!/bin/bash

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
SETUP_DIR="$DOTFILES_DIR/scripts/setup.d"
MODULE_DIR="$SETUP_DIR/modules"

source "$DOTFILES_DIR/zsh/functions.sh"

export DOTFILES_DIR

# q-ask "Enable proxy(http://127.0.0.1:1080) before setup? " && export http_proxy=http://${HTTP_PROXY:-127.0.0.1:1080} && export https_proxy=http://${HTTP_PROXY:-127.0.0.1:1080}

mkdir -p "$HOME/.config"
mkdir -p "$HOME/.ssh"

# 识别mac
if [ "$(uname)" = "Darwin" ]; then
  if [[ ! -f "$HOME/.mac" ]]; then
    touch "$HOME/.mac"
  fi
fi

if [ -d "$MODULE_DIR" ]; then
  modules=("$MODULE_DIR"/*.sh)
  if [ "${#modules[@]}" -gt 1 ]; then
    IFS=$'\n' modules=($(printf '%s\n' "${modules[@]}" | LC_ALL=C sort -V))
  fi
  if [ ! -e "${modules[0]}" ]; then
    modules=()
  fi

  if [ "${#modules[@]}" -gt 0 ]; then
    selections=()
    module_tags=()
    module_descs=()

    for module_file in "${modules[@]}"; do
      tag="$(basename "$module_file")"
      desc="$(sed -n 's/^# DESC: //p' "$module_file" | head -n1)"
      if [[ -z "$desc" ]]; then
        desc="$tag"
      fi
      module_tags+=("$tag")
      module_descs+=("$desc")
      selections+=(0)
    done

    cursor=0
    total="${#modules[@]}"

    render_menu() {
      printf "\033[2J\033[H"
      echo "Select modules to run:"
      echo "Use ↑/↓ or j/k to move, Space to toggle, Enter to run, q to quit."
      echo
      for i in "${!module_tags[@]}"; do
        marker="[ ]"
        if [ "${selections[$i]}" -eq 1 ]; then
          marker="[x]"
        fi
        pointer="  "
        if [ "$i" -eq "$cursor" ]; then
          pointer="> "
        fi
        printf "%s%s %s - %s\n" "$pointer" "$marker" "${module_tags[$i]}" "${module_descs[$i]}"
      done
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
      fi
      echo "$k"
    }

    render_menu
    while :; do
      key="$(read_key)"
      case "$key" in
        "q")
          exit 0
          ;;
        "")
          break
          ;;
        " ")
          if [ "${selections[$cursor]}" -eq 1 ]; then
            selections[$cursor]=0
          else
            selections[$cursor]=1
          fi
          ;;
        "j" | "ESC[B")
          cursor=$((cursor + 1))
          if [ "$cursor" -ge "$total" ]; then cursor=0; fi
          ;;
        "k" | "ESC[A")
          cursor=$((cursor - 1))
          if [ "$cursor" -lt 0 ]; then cursor=$((total - 1)); fi
          ;;
      esac
      render_menu
    done

    selected=()
    for i in "${!module_tags[@]}"; do
      if [ "${selections[$i]}" -eq 1 ]; then
        selected+=("${module_tags[$i]}")
      fi
    done

    if [ "${#selected[@]}" -eq 0 ]; then
      echo "No modules selected. Exit."
      exit 1
    fi

    contains_selected() {
      local tag="$1"
      local s
      for s in "${selected[@]}"; do
        if [[ "$s" == "$tag" ]]; then
          return 0
        fi
      done
      return 1
    }

    for module_file in "${modules[@]}"; do
      tag="$(basename "$module_file")"
      if contains_selected "$tag"; then
        bash "$module_file"
        status=$?
        if [ $status -eq 0 ]; then
          echo "done: $tag"
        else
          echo "failed($status): $tag"
        fi
        echo "Press Enter to continue..."
        read -r
      fi
    done
  fi
fi

# q-ask "Install pip3 requirements?" && sh "$DOTFILES_DIR/scripts/pip3-requirements.sh"
