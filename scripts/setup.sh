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

ask "Clone parcker.nvim?" && git clone --depth 1 https://github.com/wbthomason/packer.nvim ~/.local/share/nvim/site/pack/packer/start/packer.nvim

ask "Use ssh config?" && ln -s ~/.dotfiles/.ssh/config ~/.ssh/config

ask "Download stardict?" && sh ~/.dotfiles/scripts/download-stardict.sh

ask "Git config?" && ln -s ~/.dotfiles/.gitconfig ~/.gitconfig

if [ "$(uname)" = "Linux" ]; then
    if [ -f /etc/lsb-release ]; then
        ask "Add add-apt-repository?" && sh ~/.dotfiles/scripts/apt-ppa.sh
        ask "Install requires(apt)?" && sh ~/.dotfiles/scripts/apt-requires.sh
    fi
    ask "Config pip3 ali index-url?" && sh ~/.dotfiles/scripts/pip3-ali.sh
fi

ln -s ~/.dotfiles/.vim ~/.vim
ln -s ~/.dotfiles/.ideavimrc ~/.ideavimrc
ln -s ~/.dotfiles/.zshrc ~/.zshrc
# ln -s ~/.dotfiles/.p10k.zsh ~/.p10k.zsh
ln -s ~/.dotfiles/zsh/lu5je0.zsh-theme ~/.oh-my-zsh/themes/lu5je0.zsh-theme

if [ "$(uname)" = "Darwin" ]; then
    if [[ -f ~/.mac ]]; then
        touch ~/.mac
    fi
fi

mkdir -p ~/.bin
ln -s ~/.dotfiles/bin ~/.bin/local

mkdir -p ~/.pip
ln -s ~/.dotfiles/.pip/pip.conf ~/.pip/pip.conf
ln -s ~/.dotfiles/.tmux.conf ~/.tmux.conf

mkdir -p ~/.aria2
ln -s ~/.dotfiles/.aria2/aria2.conf ~/.aria2/aria2.conf

# nvim
mkdir -p ~/.local/share/nvim
ln -s ~/.dotfiles/.vim ~/.local/share/nvim/site
mkdir -p ~/.config/nvim
ln -s ~/.dotfiles/.vim/vimrc ~/.config/nvim/init.vim
ln -s ~/.dotfiles/.vim/coc-settings.json ~/.config/nvim/coc-settings.json

rm ~/.dotfiles/.vim/.vim
rm ~/.dotfiles/bin/bin
