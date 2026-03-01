if [[ -f "$HOME/.config/q-secret-env/master.pass" || -f "$HOME/.config/lu5je0/q-secret-env/master.pass" ]]; then
  q-secret-env --sync >/dev/null 2>&1
  [[ -f "$HOME/.config/q-secret-env/env.zsh" ]] && source "$HOME/.config/q-secret-env/env.zsh"
fi
