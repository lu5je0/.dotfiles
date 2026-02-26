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
  if [ ! -e "${modules[0]}" ]; then
    modules=()
  fi

  if [ "${#modules[@]}" -gt 0 ]; then
    if command -v whiptail >/dev/null 2>&1; then
      ui_cmd="whiptail"
    elif command -v dialog >/dev/null 2>&1; then
      ui_cmd="dialog"
    else
      echo "whiptail/dialog not found. Please install one to use TUI checklist."
      exit 1
    fi

    options=()
    for module_file in "${modules[@]}"; do
      desc="$(sed -n 's/^# DESC: //p' "$module_file" | head -n1)"
      if [[ -z "$desc" ]]; then
        desc="$(basename "$module_file")"
      fi
      options+=("$(basename "$module_file")" "$desc" "OFF")
    done

    selection=$("$ui_cmd" --title "Dotfiles Setup" --checklist "Select modules to run:" 20 78 12 "${options[@]}" 3>&1 1>&2 2>&3)
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
      exit 0
    fi

    selection="${selection//\"/}"
    read -r -a selected <<< "$selection"

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
      fi
    done
  fi
fi

# q-ask "Install pip3 requirements?" && sh "$DOTFILES_DIR/scripts/pip3-requirements.sh"
