if [[ -n $WSL_DISTRO_NAME ]]; then
  function disable_ime_cmd {
    "/mnt/d/bin/toDisableIME.exe"
  }
  function enable_ime_cmd {
    "/mnt/d/bin/toDisableIME.exe"
  }
# elif [[ $UNAME_INFO =~ "Darwin" ]]; then
else
  function disable_ime_cmd {
    printf "\033]1337;SetUserVar=tui-bridge=eyJpZCI6MSwibW9kdWxlIjoiaW1lIiwibWV0aG9kIjoibm9ybWFsIiwicGFyYW1zIjp7fX0=\007"
  }
  function enable_ime_cmd {
    printf "\033]1337;SetUserVar=tui-bridge=eyJpZCI6MSwibW9kdWxlIjoiaW1lIiwibWV0aG9kIjoiaW5zZXJ0IiwicGFyYW1zIjp7fX0=\007"
  }
fi

# Keep the IME in sync with the vi keymap.
#
# kitty disables its IME outright for the window (see the kitty fork's
# agents.md), so unlike a plain input-source switch there is no way to bring it
# back by hand -- every path into insert mode has to re-enable it explicitly.
# Hooking the keymap hooks covers all of them (i a o O s S c C R /, visual, ...)
# without a widget per key.
#
# vi-mode.zsh is sourced first and defines these hooks for the cursor shape, so
# wrap them rather than redefining.

function _vi-im-apply-for-keymap() {
  # Grouped the same way as _vi-mode-set-cursor-shape-for-keymap
  case "${1:-${KEYMAP:-main}}" in
    main|viins|isearch|command) enable_ime_cmd ;;
    *)                          disable_ime_cmd ;;
  esac
}

functions -c zle-keymap-select _vi-im-prev-keymap-select
function zle-keymap-select() {
  _vi-im-prev-keymap-select "$@"
  _vi-im-apply-for-keymap "$KEYMAP"
}
zle -N zle-keymap-select

# A fresh prompt always starts in insert mode, and paths like Ctrl-C can skip
# zle-keymap-select entirely, so re-enable here as the safety net.
functions -c zle-line-init _vi-im-prev-line-init
function zle-line-init() {
  _vi-im-prev-line-init "$@"
  enable_ime_cmd
}
zle -N zle-line-init

# Never leave the IME disabled while a command runs.
functions -c zle-line-finish _vi-im-prev-line-finish
function zle-line-finish() {
  _vi-im-prev-line-finish "$@"
  enable_ime_cmd
}
zle -N zle-line-finish
