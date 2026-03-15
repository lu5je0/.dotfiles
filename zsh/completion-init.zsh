fpath=($HOME/.dotfiles/zsh/completions $fpath)
autoload -Uz compinit

_ZSH_COMPDUMP_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
_ZSH_COMPDUMP_FILE="$_ZSH_COMPDUMP_DIR/zcompdump-${ZSH_VERSION}"

# (#qN.mh+24) means: treat the path as a glob in [[ ]], allow no-match,
# and match files whose mtime is older than 24 hours.
if [[ ! -s $_ZSH_COMPDUMP_FILE || -n "$_ZSH_COMPDUMP_FILE"(#qN.mh+24) ]]; then
  # -d specifies the dump file path.
  compinit -d "$_ZSH_COMPDUMP_FILE"
else
  # -C skips the new-completion check and reuses the existing dump for faster startup.
  compinit -C -d "$_ZSH_COMPDUMP_FILE"
fi

# Replay compdefs captured by zinit before compinit, mainly from delayed plugins.
zinit cdreplay -q
