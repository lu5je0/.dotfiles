# mac
if [ "$(uname)" = "Darwin" ]; then
    PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
    alias ls='ls -F --show-control-chars --color=auto'
    eval `gdircolors -b $HOME/.dir_colors`
    export JAVA_HOME_8=/Library/Java/JavaVirtualMachines/adoptopenjdk-8.jdk/Contents/Home
    export JAVA_HOME_11=/Library/Java/JavaVirtualMachines/openjdk-11.0.2.jdk/Contents/Home
    export JAVA_HOME_17=/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home
    alias jdk8='export JAVA_HOME=$JAVA_HOME_8'
    alias jdk11='export JAVA_HOME=$JAVA_HOME_11'
    alias jdk17='export JAVA_HOME=$JAVA_HOME_17'
    alias e='open'
    alias sed='gsed'
    alias iterm='open -a iTerm .'
    export JAVA_HOME=$JAVA_HOME_17
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#555555"
elif [ $(uname -r | sed -n 's/.*\( *Microsoft *\).*/\1/ip') ]; then
    alias e='explorer.exe'
    alias cmd='/mnt/c/Windows/System32/cmd.exe /c'
    clippaste () {
        powershell.exe -noprofile -command Get-Clipboard | tr -d '\r'
    }
fi
