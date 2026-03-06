# zmodload zsh/zprof

##########################################
# zinit
##########################################
if [[ ! -d $HOME/.local/share/zinit/zinit.git ]]; then
  git clone --depth=1 https://github.com/zdharma-continuum/zinit.git ~/.local/share/zinit/zinit.git
fi
source ~/.local/share/zinit/zinit.git/zinit.zsh

export UNAME_INFO=$(uname -a)

setopt AUTO_CD
setopt NO_BEEP

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

# zinit ice lucid wait='0'
# wsl中git定制，所以不能wait
zinit snippet OMZ::lib/git.zsh

# zinit ice lucid wait='1'
zinit snippet OMZ::plugins/git/git.plugin.zsh

zinit ice lucid wait='1'
zinit snippet OMZ::plugins/colored-man-pages/colored-man-pages.plugin.zsh

##########################################
# plugins
##########################################

zinit ice depth=1 lucid wait='0'
zinit light zsh-users/zsh-syntax-highlighting

zinit ice depth=1 lucid wait='0'
zinit light hlissner/zsh-autopair

zinit ice depth=1 lucid wait='1'
zinit light zsh-users/zsh-history-substring-search

# zinit ice lucid wait='0' atload='_zsh_autosuggest_start'
# zinit light zsh-users/zsh-autosuggestions
# bindkey '^K' autosuggest-accept

# 额外补全
zinit ice depth=1 lucid wait='0'
zinit light zsh-users/zsh-completions
zinit ice depth=1 lucid wait='1'
zinit light matthieusb/zsh-sdkman

##########################################
# 本地sh文件
##########################################

zinit ice lucid wait='0'
zinit snippet ~/.dotfiles/zsh/zoxide.sh

# zinit ice lucid wait='1'
zinit snippet ~/.dotfiles/zsh/platform.sh

zinit ice lucid wait='1'
zinit snippet ~/.dotfiles/zsh/functions.sh

zinit ice lucid wait='1'
zinit snippet ~/.dotfiles/zsh/proxy.sh

zinit ice lucid wait='1'
zinit snippet ~/.dotfiles/zsh/secret-env.zsh

zinit snippet ~/.dotfiles/zsh/vi-mode.zsh
zinit snippet ~/.dotfiles/zsh/vi-im-switch.zsh

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
export LS_COLORS="rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=01;34:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.axv=01;35:*.anx=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.axa=00;36:*.oga=00;36:*.spx=00;36:*.xspf=00;36:"
export NODE_NO_WARNINGS=1
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8


##########################################
# alias
##########################################
alias pc="proxychains4 -q"
# alias sftp="sftp -C"
alias crontab="cron.sh"

alias ls='ls -F --show-control-chars --color=auto'

# alias rm="trash"

alias sudo='sudo env PATH=/sbin:$PATH'
alias sudo-default-path='\sudo'

# alias sudo="sudo "
# alias sudo-with-path='sudo env PATH=$PATH'

alias awk-map-count="awk '{a[\$1]++} END {for (i in a) print i,a[i]}'"

alias speedtest-jp='speedtest -s 60324'
alias speedtest-sg='speedtest -s 367'
alias speedtest-sh='speedtest -s 24447'
alias speedtest-hk='speedtest -s 1536'
alias speedtest-js='speedtest -s 5396'
alias speedtest-los='speedtest -s 5905'
alias speedtest-de='speedtest -s 44081'

# ls
# alias l='ls -lah'
# alias ll='ls -lh'

alias ll='eza -laF'
alias l='eza -lF'

alias rz='trz'
alias sz='tsz'

alias grep='grep --color'

alias ntpdate-aliyun='sudo ntpdate -u time1.aliyun.com'


alias time-204='time curl "https://www.gstatic.com/generate_204"'
alias time-204-http='time curl "http://www.gstatic.com/generate_204"'

alias curl-post-json='curl -H "Content-Type:application/json" -X POST'

# tmux
alias td="tmux detach"
alias tl="tmux ls"
alias tkss="tmux kill-session -t"
# alias ta="tmux attach -t"
alias tn="tmux new-session -s"
function ta() {
    # 检查是否提供了会话名
    if [ -z "$1" ]; then
        echo "Usage: ta <session-name>"
        return 1
    fi

    # 尝试连接到会话，如果不存在则创建
    if tmux has-session -t "$1" 2>/dev/null; then
      tmux attach -t "$1"
    else
      tmux new-session -s "$1"
    fi
}

# nvim
alias vi='nvim'
alias vim='nvim'
alias vimn='nvim -u None'

# maven
alias mvni='mvn install -Dmaven.test.skip=true'
alias mvnp='mvn package -Dmaven.test.skip=true'

export HOMEBREW_NO_AUTO_UPDATE=1

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

fzf-history-widget() {
  # BUFFER=$(history -n 1 | fzf --height 40% --reverse --tiebreak=index --no-sort --exact --smart-case)
  # CURSOR=$#BUFFER
  
  local selected
  # 获取历史记录（按时间倒序 + 去行号）
  selected=$(fc -rl 1 | sed 's/^ *[0-9]* *//' | fzf --height 40% --reverse --tiebreak=index --no-sort --exact --smart-case)

  if [[ -n "$selected" ]]; then
    # 将选中内容插入到当前光标位置
    BUFFER="${BUFFER:0:$CURSOR}${selected}${BUFFER:$CURSOR}"
    # 更新光标位置
    CURSOR=$(( CURSOR + ${#selected} ))
  fi
  
  zle reset-prompt
}
zle -N fzf-history-widget
bindkey '^R' fzf-history-widget

fzf-search-widget() {
  local file
  file=$(fdfind --type f --hidden --exclude .git 2>/dev/null | fzf --height 40% --reverse)

  if [[ -n "$file" ]]; then
    # 转义特殊字符并插入到当前光标位置
    local escaped_file
    escaped_file=$(printf '%q' "$file")
    # 将转义后的文件名插入到光标所在位置
    BUFFER="${BUFFER:0:$CURSOR}${escaped_file}${BUFFER:$CURSOR}"
    # 移动光标到插入内容之后
    CURSOR=$(( CURSOR + ${#escaped_file} ))
  fi
  zle reset-prompt
}
zle -N fzf-search-widget
bindkey '^F' fzf-search-widget

fzf-zoxide-widget() {
  local file
  file=$(zoxide query --interactive)

  if [[ -n "$file" ]]; then
    # 转义特殊字符并插入到当前光标位置
    local escaped_file
    escaped_file=$(printf '%q' "$file")
    # 将转义后的文件名插入到光标所在位置
    BUFFER="${BUFFER:0:$CURSOR}${escaped_file}${BUFFER:$CURSOR}"
    # 移动光标到插入内容之后
    CURSOR=$(( CURSOR + ${#escaped_file} ))
  fi
  zle reset-prompt
}
zle -N fzf-zoxide-widget
bindkey '^G' fzf-zoxide-widget

bindkey '^P' history-substring-search-up
bindkey '^N' history-substring-search-down

# 补全
# 0 -- vanilla completion (abc => abc)
# 1 -- smart case completion (abc => Abc)
# 2 -- word flex completion (abc => A-big-Car)
# 3 -- full flex completion (abc => ABraCadabra)
# zstyle ':completion:*' matcher-list '' \
#   'm:{a-z\-}={A-Z\_}' \
#   'r:[^[:alpha:]]||[[:alpha:]]=** r:|=* m:{a-z\-}={A-Z\_}' \
#   'r:|?=** m:{a-z\-}={A-Z\_}'

setopt ignore_eof
function bash-ctrl-d() {
  if [[ $CURSOR == 0 && -z $BUFFER ]]; then
    [[ -z $IGNOREEOF || $IGNOREEOF == 0 ]] && exit
    if [[ "$LASTWIDGET" == "bash-ctrl-d" ]]; then
      ((--__BASH_IGNORE_EOF <= 1)) && exit
    else
      echo 'Press Ctrl+D again to exit the shell.'
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

fpath=($HOME/.dotfiles/zsh/completions $fpath)
autoload -Uz compinit && compinit -C

# rustup
if [[ -d $HOMEBREW_PATH/opt/rustup/bin ]]; then
  export PATH="$HOMEBREW_PATH/opt/rustup/bin:$PATH"
fi

if [[ ! -f ~/.ohmyenv ]]; then
  touch ~/.ohmyenv
  echo "# export PATH=~/.local/share/neovim/bin:$PATH\n# export USER_HTTP_PROXY='http://127.0.0.1:1081'" >~/.ohmyenv
fi
source ~/.ohmyenv

# THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  zinit ice lucid wait='1'
  zinit snippet "$HOME/.sdkman/bin/sdkman-init.sh"
fi
