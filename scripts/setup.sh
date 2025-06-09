#!/bin/bash

source ~/.dotfiles/zsh/functions.sh

q-ask "Enable proxy(http://127.0.0.1:1080) before setup? " && export http_proxy=http://${HTTP_PROXY:-127.0.0.1:1080} && export https_proxy=http://${HTTP_PROXY:-127.0.0.1:1080}

if [[ ! -d ~/.config ]]; then
  mkdir -p ~/.config
fi

if [ "$(uname)" = "Linux" ]; then
  if [ -f /etc/lsb-release ]; then
    # q-ask "Add add-apt-repository?" && sh ~/.dotfiles/scripts/apt-ppa.sh
    q-ask "Install requires(apt)?" && sh ~/.dotfiles/scripts/apt-requirements.sh
    # q-ask "Update nodejs?" && curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash - && sudo apt install -y nodejs
  fi
  q-ask "Config pip3 ali index-url?" && sh ~/.dotfiles/scripts/pip3-ali.sh
fi

if [[ -f ~/.ssh/config ]]; then
  mkdir -p ~/.ssh/config
else
  ln -s ~/.dotfiles/ssh/config ~/.ssh/config
fi

q-ask "download stardict?" && sh ~/.dotfiles/scripts/download-stardict.sh

q-ask "ln -s ~/.dotfiles/git ~/.config/git?" && ln -s ~/.dotfiles/git ~/.config/git

q-ask "ln -s ~/.dotfiles/.hammerspoon ~/.hammerspoon?" && ln -s ~/.dotfiles/.hammerspoon ~/.hammerspoon

q-ask "ln -s ~/.dotfiles/termux ~/.config/termux?" && ln -s ~/.dotfiles/termux ~/.config/termux

q-ask "copy maven config?" && if [[ ! -d ~/.m2 ]]; then mkdir ~/.m2; fi && cp -i ~/.dotfiles/m2/settings.xml ~/.m2/settings.xml

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
if [[ ! -f ~/.local/bin/solid ]]; then
  ln -s ~/.dotfiles/bin ~/.local/bin/solid
fi

if [[ ! -d ~/.config/pip ]]; then
  ln -s ~/.dotfiles/pip ~/.config/pip
fi

if [[ ! -d ~/.config/karabiner ]]; then
  ln -s ~/.dotfiles/karabiner ~/.config/karabiner
fi

# tmux
# if [[ ! -d ~/.tmux/plugins/tpm ]]; then
#     git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
# fi
if [[ ! -d ~/.config/tmux ]]; then
  ln -s ~/.dotfiles/tmux ~/.config/tmux
fi

# wezterm
# if [[ ! -d ~/.config/wezterm ]]; then
#     ln -s ~/.dotfiles/wezterm ~/.config/wezterm
# fi

# kitty
if [[ ! -d ~/.config/kitty ]]; then
  ln -s ~/.dotfiles/kitty ~/.config/kitty
fi

# alacritty
# if [[ ! -d ~/.config/alacritty ]]; then
#   ln -s ~/.dotfiles/alacritty/mac/alacritty.yml ~/.config/alacritty/alacritty.yml
# fi

# mkdir -p ~/.aria2
# ln -s ~/.dotfiles/aria2/aria2.conf ~/.aria2/aria2.conf

# nvim
if [[ ! -d ~/.config/nvim ]]; then
  q-ask "config neovim?" && ln -s ~/.dotfiles/vim ~/.config/nvim
fi

# q-ask "Install pip3 requirements?" && sh ~/.dotfiles/scripts/pip3-requirements.sh
