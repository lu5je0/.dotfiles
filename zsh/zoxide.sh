if command -v zoxide > /dev/null 2>&1; then
  unalias zi
  eval "$(zoxide init zsh)"
fi
