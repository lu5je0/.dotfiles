fpath=($HOME/.dotfiles/zsh/completions $fpath)
autoload -Uz compinit

_ZSH_COMPDUMP_FILE="$HOME/.zcompdump-${ZSH_VERSION}"

# Use array glob to check if dump file is older than 24 hours.
# Glob qualifiers don't work inside [[ ]], so we expand into an array.
_zcompdump_stale=( "$_ZSH_COMPDUMP_FILE"(Nmh+24) )
if [[ ! -s $_ZSH_COMPDUMP_FILE ]] || (( ${#_zcompdump_stale} )); then
  compinit -d "$_ZSH_COMPDUMP_FILE"
else
  compinit -C -d "$_ZSH_COMPDUMP_FILE"
fi
unset _zcompdump_stale

# Replay compdefs captured by zinit before compinit, mainly from delayed plugins.
zinit cdreplay -q
