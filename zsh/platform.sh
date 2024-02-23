# mac
if [[ $UNAME_INFO =~ "Darwin" ]]; then
  # todo
  # intel
  # PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
  
  # arm
  export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
  export PATH="/opt/homebrew/opt/grep/libexec/gnubin:$PATH"
  
  alias ls='ls -F --show-control-chars --color=auto'
  eval $(gdircolors -b $HOME/.dir_colors)
  export JAVA_HOME_8='/Users/lu5je0/Library/Java/JavaVirtualMachines/azul-1.8.0_352/Contents/Home'
  export JAVA_HOME_11='/Users/lu5je0/Library/Java/JavaVirtualMachines/temurin-11.0.17/Contents/Home'
  export JAVA_HOME_17='/Users/lu5je0/Library/Java/JavaVirtualMachines/temurin-17.0.5-2/Contents/Home'
  alias jdk8='export JAVA_HOME=$JAVA_HOME_8'
  alias jdk11='export JAVA_HOME=$JAVA_HOME_11'
  alias jdk17='export JAVA_HOME=$JAVA_HOME_17'
  alias e='open'
  alias sed='gsed'
  alias yy='pbcopy'
  alias p='pbpaste'
  alias iterm='open -a iTerm .'
  
  if test -z "$JAVA_HOME";then
    export JAVA_HOME=$JAVA_HOME_8
  fi
  
  export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#555555"

  # brew
  export HOMEBREW_NO_AUTO_UPDATE=true

  # iterm title bar
  echo -en "\033]6;1;bg;red;brightness;44\a"
  echo -en "\033]6;1;bg;green;brightness;46\a"
  echo -en "\033]6;1;bg;blue;brightness;51\a"
elif [[ $UNAME_INFO =~ "icrosoft" ]]; then # wsl1=microsoft wsl2:Microsoft
  function __git_prompt_git() {
    if [[ "$PWD" =~ '^/mnt/[cdefgh]/' ]]; then
      command git.exe "$@"
    else
      command git "$@"
    fi
  }
  export WSL_IP=$(hostname -I | awk '{print $1}')
  export WSL_HOST_IP=$(cat /etc/resolv.conf | grep nameserver | awk '{ print $2 }')
  alias gst='__git_prompt_git status'
  alias gaa='__git_prompt_git add -A'
  alias gc='__git_prompt_git commit'
  alias gd='__git_prompt_git diff'
  alias grep='grep --color'
  alias e='/mnt/c/Windows/explorer.exe'
  alias yy='win32yank.exe -i'
  alias p='win32yank.exe -o'
  alias cmd='/mnt/c/Windows/System32/cmd.exe /c'
  export PATH=$PATH:'/mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/'
  export PATH=~/.dotfiles/bin/wsl/:$PATH
  export PATH=/mnt/c/Users/lu5je0/scoop/shims:$PATH
  clippaste() {
    powershell.exe -noprofile -command Get-Clipboard | tr -d '\r'
  }
  
  vi-escape() {
    ~/.dotfiles/vim/lib/toDisableIME.exe
    zle vi-cmd-mode
  }
elif [[ $UNAME_INFO =~ "Android" ]]; then
  alias apk-install='termux-open --view --content-type "application/vnd.android.package-archive" '
fi

if [[ $UNAME_INFO =~ "GNU/Linux" ]]; then
  # export JAVA_HOME='/home/linuxbrew/.linuxbrew/Cellar/openjdk@11/11.0.22'
fi
