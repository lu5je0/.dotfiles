if [[ $UNAME_INFO =~ "microsoft" ]]; then
    vi-escape-im() {
    ~/.dotfiles/vim/lib/toDisableIME.exe
    zle vi-cmd-mode
    }
    zle -N vi-escape-im
    bindkey "^[" vi-escape-im

    # vi-insert-im() {
    # ~/.dotfiles/vim/lib/toEnableIME.exe
    # zle vi-insert
    # }
    # zle -N vi-insert-im
    # bindkey -a i vi-insert-im
    #
    # vi-add-eol-im() {
    # ~/.dotfiles/vim/lib/toEnableIME.exe
    # zle vi-add-eol
    # }
    # zle -N vi-add-eol-im
    # bindkey -a A vi-add-eol-im
    #
    # vi-insert-bol-im() {
    # ~/.dotfiles/vim/lib/toEnableIME.exe
    # zle vi-insert-bol
    # }
    # zle -N vi-insert-bol-im
    # bindkey -a I vi-insert-bol-im
    #
    # vi-open-line-above-im() {
    # ~/.dotfiles/vim/lib/toEnableIME.exe
    # zle vi-open-line-above
    # }
    # zle -N vi-open-line-above-im
    # bindkey -a O vi-open-line-above-im
    #
    # vi-open-line-below-im() {
    # ~/.dotfiles/vim/lib/toEnableIME.exe
    # zle vi-open-line-below
    # }
    # zle -N vi-open-line-below-im
    # bindkey -a o vi-open-line-below-im
    #
    # vi-substitute-im() {
    # ~/.dotfiles/vim/lib/toEnableIME.exe
    # zle vi-substitute
    # }
    # zle -N vi-substitute-im
    # bindkey -a s vi-substitute-im
    #
    # vi-substitute-im() {
    # ~/.dotfiles/vim/lib/toEnableIME.exe
    # zle vi-substitute
    # }
    # zle -N vi-substitute-im
    # bindkey -a s vi-substitute-im
fi

