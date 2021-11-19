#!/bin/bash

ask() {
    echo -n $1
    echo -n $' (y/n) \n# '
    read choice
    case $choice in
        Y | y)
        return 0
    esac
    return -1
}

ask "Enable http proxy(http://127.0.0.1:1080)?" && export http_proxy=http://${HTTP_PROXY:-127.0.0.1:1080} && export https_proxy=http://${HTTP_PROXY:-127.0.0.1:1080}

if [ "$(uname)" = "Linux" ]; then
    if [ -f /etc/lsb-release ]; then
        ask "Add add-apt-repository?" && sh ~/.dotfiles/scripts/apt-ppa.sh
        ask "Install requires(apt)?" && sh ~/.dotfiles/scripts/apt-requirements.sh
        ask "Update nodejs?" && curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash - && sudo apt install -y nodejs
    fi
    ask "Config pip3 ali index-url?" && sh ~/.dotfiles/scripts/pip3-ali.sh
fi

if [[ -f ~/.ssh/config ]]; then
    cp ~/.dotfiles/ssh/config ~/.ssh/config
else
    echo "~/.ssh/config existed"
fi

ask "Download stardict?" && sh ~/.dotfiles/scripts/download-stardict.sh

ask "Git config?" && ln -s ~/.dotfiles/.gitconfig ~/.gitconfig

ask "Copy maven config?" && if [[ ! -d ~/.m2 ]]; then mkdir ~/.m2; fi && cp -i ~/.dotfiles/m2/settings.xml ~/.m2/settings.xml

ln -s ~/.dotfiles/ideavimrc ~/.ideavimrc
ln -s ~/.dotfiles/zshrc ~/.zshrc

if [[ ! -d ~/.cheat ]]; then
    ln -s ~/.dotfiles/cheat ~/.cheat
fi

if [ "$(uname)" = "Darwin" ]; then
    if [[ -f ~/.mac ]]; then
        touch ~/.mac
    fi
fi

if [[ ! -d ~/.local/bin ]]; then
    mkdir -p ~/.local/bin
fi
ln -s ~/.dotfiles/bin ~/.local/bin/solid

mkdir -p ~/.pip
ln -s ~/.dotfiles/pip/pip.conf ~/.pip/pip.conf
ln -s ~/.dotfiles/tmux.conf ~/.tmux.conf

mkdir -p ~/.aria2
ln -s ~/.dotfiles/aria2/aria2.conf ~/.aria2/aria2.conf

# nvim
mkdir -p ~/.config

if [[ ! -d ~/.config/nvim ]]; then
    ln -s ~/.dotfiles/vim ~/.config/nvim
fi

ask "Install pip3 requirements?" && sh ~/.dotfiles/scripts/pip3-requirements.sh

if [ "$(uname)" = "Darwin" ]; then
    ask "pip3 install pyobjc?" && pip3 install pyobjc
fi
