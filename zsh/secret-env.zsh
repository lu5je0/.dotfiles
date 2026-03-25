if [[ -f "$HOME/.config/q-secret-env/master.pass" || -f "$HOME/.config/lu5je0/q-secret-env/master.pass" ]]; then
  local _enc_file="${DOTFILES_DIR:-$HOME/.dotfiles}/secrets/q-secret-env.enc"
  local _env_file="$HOME/.config/q-secret-env/env.zsh"

  # Sync only if enc file is newer than env.zsh or env.zsh doesn't exist
  if [[ -f "$_enc_file" && ( ! -f "$_env_file" || "$_enc_file" -nt "$_env_file" ) ]]; then
    q-secret-env sync >/dev/null 2>&1
  fi

  [[ -f "$_env_file" ]] && source "$_env_file"
fi
