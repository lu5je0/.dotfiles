# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

##########################################
# zinit
##########################################
if [[ ! -d ~/.local/share/zinit/zinit.git ]]; then
  git clone --depth=1 https://github.com/zdharma-continuum/zinit.git ~/.local/share/zinit/zinit.git
fi
source ~/.local/share/zinit/zinit.git/zinit.zsh

export UNAME_INFO=$(uname -a)
autoload -Uz compinit && compinit

setopt AUTO_CD

# 设置 Zsh 在命令补全时删除后缀的字符，只设置一个空格，那么只有空格会被删除。
# If ZLE_REMOVE_SUFFIX_CHARS is not set, the default behaviour is equivalent to: 
# ZLE_REMOVE_SUFFIX_CHARS=$' \t\n;&|'
export ZLE_REMOVE_SUFFIX_CHARS=''

##########################################
# OMZ
##########################################
zinit snippet OMZ::lib/completion.zsh
zinit snippet OMZ::lib/history.zsh
zinit snippet OMZ::lib/key-bindings.zsh
zinit snippet OMZ::lib/git.zsh
# 注释后没有文件颜色
zinit snippet OMZ::lib/theme-and-appearance.zsh

# zinit ice lucid wait='0'
zinit snippet OMZ::plugins/git/git.plugin.zsh
unalias gcp

zinit ice lucid wait='1'
zinit snippet OMZ::plugins/colored-man-pages/colored-man-pages.plugin.zsh

##########################################
# plugins
##########################################

zinit ice depth=1 lucid wait='1'
zinit light paulirish/git-open

zinit ice depth=1 lucid wait='0'
zinit light zsh-users/zsh-syntax-highlighting

zinit ice depth=1 lucid wait='0'
zinit light hlissner/zsh-autopair

# zinit ice lucid wait='0' atload='_zsh_autosuggest_start'
# zinit light zsh-users/zsh-autosuggestions

# 额外补全
zinit ice depth=1 lucid wait='0'
zinit light zsh-users/zsh-completions

##########################################
# 本地sh文件
##########################################

zinit snippet ~/.dotfiles/zsh/z/z.sh

# zinit ice lucid wait='1'
zinit snippet ~/.dotfiles/zsh/platform.sh

zinit ice lucid wait='1'
zinit snippet ~/.dotfiles/zsh/functions.sh

zinit ice lucid wait='1'
zinit snippet ~/.dotfiles/zsh/proxy.sh

zinit snippet ~/.dotfiles/zsh/vi-mode.zsh
zinit snippet ~/.dotfiles/zsh/vi-im-switch.zsh

# zinit wait'2' lucid \
#   atinit"source $ZHOMEDIR/rc/pluginconfig/per-directory-history.zsh" \
#   atload"_per-directory-history-set-global-history" \
#   light-mode for @CyberShadow/per-directory-history
# https://github.com/jimhester/per-directory-history/issues/21
# https://github.com/jimhester/per-directory-history/issues/27

##########################################
# theme
##########################################

# zinit snippet ~/.dotfiles/zsh/lu5je0.zsh-theme # lu5je0 

# p10k
zinit ice depth=1
zinit light romkatv/powerlevel10k
source ~/.dotfiles/zsh/p10k.zsh

##########################################
# zsh key mappings
##########################################
bindkey "^[[5~" history-beginning-search-backward
bindkey "^[[6~" history-beginning-search-forward
# bindkey "^n" autosuggest-accept


##########################################
# ENV
##########################################
export ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=""
export PATH=~/.local/bin:~/.local/bin/solid:$PATH
export PATH=$PATH:~/go/bin
export EDITOR=nvim
export PATH=/home/lu5je0/.local/share/neovim/bin:$PATH
export LS_COLORS="rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=01;34:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.axv=01;35:*.anx=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.axa=00;36:*.oga=00;36:*.spx=00;36:*.xspf=00;36:"
export NODE_NO_WARNINGS=1
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8


##########################################
# alias
##########################################
alias pc="proxychains4 -q"
# alias sftp="sftp -C"
alias wd="~/.dotfiles/submodule/wd/wd.py"
alias fpp="~/.dotfiles/submodule/PathPicker/fpp"
alias fetch-subs="~/.dotfiles/submodule/SubtitlesDownloader/fetch_subs.py"
alias crontab="cron.sh"

alias sudo='sudo env PATH=$PATH'
alias sudo-default-path='\sudo'

# alias sudo="sudo "
# alias sudo-with-path='sudo env PATH=$PATH'

alias awk-map-count="awk '{a[\$1]++} END {for (i in a) print i,a[i]}'"

# git
alias gcof='git checkout `git branch | fzf`'

alias speedtest-hz='speedtest -s 54312'
alias speedtest-hk='speedtest -s 1536'
alias speedtest-js='speedtest -s 5396'

# ls
# alias l='ls -lah'
# alias ll='ls -lh'

alias ll='exa -laF'
alias l='exa -lF'

alias grep='grep --color'
alias bat='batcat'

alias ntpdate-aliyun='sudo ntpdate -u time1.aliyun.com'

alias qrencode-ansi='qrencode -t ansiutf8'

alias time-204='time curl "https://www.gstatic.com/generate_204"'
alias time-204-http='time curl "http://www.gstatic.com/generate_204"'

alias curl-post-json='curl -H "Content-Type:application/json" -X POST'

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

# maven
alias mvni='mvn install -Dmaven.test.skip=true'
alias mvnp='mvn package -Dmaven.test.skip=true'

##########################################
# vi-mode
##########################################
VI_MODE_SET_CURSOR="true"

bindkey -a H vi-first-non-blank
bindkey -a L vi-end-of-line
bindkey -a j down-line
bindkey -a k up-line
bindkey -a K history-beginning-search-backward
bindkey -a J history-beginning-search-forward

end-of-buffer() {
  CURSOR=9999999
}
zle -N end-of-buffer

begin-of-buffer() {
  CURSOR=0
}
zle -N begin-of-buffer

bindkey -a gg begin-of-buffer
bindkey -a G end-of-buffer

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
# bindkey -a "m" autosuggest-accept
# bindkey -a "^n" autosuggest-accept

# 补全
# 0 -- vanilla completion (abc => abc)
# 1 -- smart case completion (abc => Abc)
# 2 -- word flex completion (abc => A-big-Car)
# 3 -- full flex completion (abc => ABraCadabra)
# zstyle ':completion:*' matcher-list '' \
#   'm:{a-z\-}={A-Z\_}' \
#   'r:[^[:alpha:]]||[[:alpha:]]=** r:|=* m:{a-z\-}={A-Z\_}' \
#   'r:|?=** m:{a-z\-}={A-Z\_}'

if [[ ! -f ~/.ohmyenv ]]; then
  touch ~/.ohmyenv
  echo "# export PATH=~/.local/share/neovim/bin:$PATH\n# export USER_HTTP_PROXY='http://127.0.0.1:1081'" >~/.ohmyenv
fi
source ~/.ohmyenv

# if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
#   exec tmux
# fi

setopt ignore_eof
function bash-ctrl-d() {
  if [[ $CURSOR == 0 && -z $BUFFER ]]; then
    [[ -z $IGNOREEOF || $IGNOREEOF == 0 ]] && exit
    if [[ "$LASTWIDGET" == "bash-ctrl-d" ]]; then
      ((--__BASH_IGNORE_EOF <= 1)) && exit
    else
      echo 'repeat ^D to exit shell'
      ((__BASH_IGNORE_EOF = IGNOREEOF))
    fi
  else
    zle delete-char-or-list
  fi
}
export IGNOREEOF=2
zle -N bash-ctrl-d
bindkey '^D' bash-ctrl-d
### End of Zinit's installer chunk

# bob
[[ -s "$HOME/.local/share/bob/nvim-bin" ]] && export PATH="$HOME/.local/share/bob/nvim-bin":$PATH

# linuxbrew
[[ -d "/home/linuxbrew/.linuxbrew/bin" ]] && export PATH="/home/linuxbrew/.linuxbrew/bin:"$PATH

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
