if command -v zoxide > /dev/null 2>&1; then
  unalias zi
  local _zoxide_cache="$HOME/.cache/zoxide-init-${ZSH_VERSION}.zsh"
  local _zoxide_bin="${commands[zoxide]}"
  if [[ ! -f $_zoxide_cache || $_zoxide_bin -nt $_zoxide_cache ]]; then
    mkdir -p "${_zoxide_cache:h}"
    zoxide init zsh >| "$_zoxide_cache"
  fi
  source "$_zoxide_cache"
fi
