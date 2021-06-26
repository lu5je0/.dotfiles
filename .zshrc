##########################################
# zinit
##########################################
if [[ ! -d ~/.zinit ]]; then
    git clone --depth=1 https://github.com/zdharma/zinit.git ~/.zinit/bin
fi
source ~/.zinit/bin/zinit.zsh

# OMZ
# zinit snippet OMZ::lib/clipboard.zsh
zinit snippet OMZ::lib/completion.zsh
zinit snippet OMZ::lib/history.zsh
zinit snippet OMZ::lib/key-bindings.zsh
zinit snippet OMZ::lib/git.zsh
zinit ice lucid wait='1'
zinit snippet OMZ::plugins/git/git.plugin.zsh
zinit ice lucid wait='2'
zinit snippet OMZ::plugins/zsh_reload/zsh_reload.plugin.zsh
zinit ice lucid wait='3'
zinit snippet OMZ::plugins/colored-man-pages/colored-man-pages.plugin.zsh

zinit ice lucid wait='2'
zinit snippet ~/.dotfiles/zsh/z/z.sh
zinit ice lucid wait='2'
zinit snippet ~/.dotfiles/zsh/platform-alias.sh

zinit ice lucid wait='1'
zinit snippet ~/.dotfiles/zsh/functions.sh
zinit snippet ~/.dotfiles/zsh/vi-mode.zsh

zinit ice lucid wait='3'
zinit light paulirish/git-open
zinit ice lucid wait='2'
zinit light zsh-users/zsh-syntax-highlighting
zinit ice lucid wait='1'
zinit light hlissner/zsh-autopair
zinit ice lucid wait='1'
zinit light zsh-users/zsh-autosuggestions

## THEME
# lu5je0
zinit snippet OMZ::lib/theme-and-appearance.zsh
zinit snippet ~/.dotfiles/zsh/lu5je0.zsh-theme

# pure
# zinit ice compile'(pure|async).zsh' pick'async.zsh' src'pure.zsh'
# zinit light sindresorhus/pure
# zstyle ':prompt:pure:prompt:*' color cyan

##########################################
# zsh key mappings
##########################################
bindkey "^[[5~" history-beginning-search-backward
bindkey "^[[6~" history-beginning-search-forward
bindkey "^n" autosuggest-accept



##########################################
# ENV
##########################################
source ~/.ohmyenv
export ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=""
export PATH=$PATH:~/.bin:~/.bin/local
export EDITOR=nvim
export LS_COLORS="rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=01;34:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.axv=01;35:*.anx=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.axa=00;36:*.oga=00;36:*.spx=00;36:*.xspf=00;36:"

##########################################
# alias
##########################################
alias pc="proxychains4 -q"
alias sftp="sftp -C"
alias wd="~/.dotfiles/submodule/wd/wd.py"
alias fetch_subs="~/.dotfiles/submodule/SubtitlesDownloader/fetch_subs.py"
alias sudo="sudo "
alias crontab="cron.sh"

# ls
alias l='ls -lah'
alias la='ls -lAh'
alias ll='ls -lh'
alias ls='ls --color=tty'
alias lsa='ls -lah'
alias md='mkdir -p'

# tmux
alias ta="tmux attach -t"
alias td="tmux detach"
alias tl="tmux ls"
alias tkss="tmux kill-session -t"
alias tn="tmux new-session -s"

# nvim
alias vi='nvim'
alias vim='nvim'
alias vimn='nvim -u None'

# 代理设置
alias proxy='export http_proxy=http://127.0.0.1:${HTTP_PROXY_PORT:-1080}; export https_proxy=http://127.0.0.1:${HTTP_PROXY_PORT:-1080};'
alias unproxy='unset http_proxy; unset https_proxy'
alias pc='proxychains4 -q'



##########################################
# vi-mode
##########################################
VI_MODE_SET_CURSOR="true"

bindkey -a H vi-first-non-blank
bindkey -a L vi-end-of-line
bindkey -a K history-beginning-search-backward
bindkey -a J history-beginning-search-forward

export KEYTIMEOUT=1

# surround
autoload -Uz surround
zle -N delete-surround surround
zle -N add-surround surround
zle -N change-surround surround
bindkey -a cs change-surround
bindkey -a ds delete-surround
bindkey -a ys add-surround
bindkey -M visual S add-surround
bindkey -a "^n" autosuggest-accept
