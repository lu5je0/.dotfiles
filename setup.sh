git clone --depth 1 https://github.com/wbthomason/packer.nvim\
 ~/.local/share/nvim/site/pack/packer/start/packer.nvim

ln -s ~/.dotfiles/.vim ~/.vim
ln -s ~/.dotfiles/.ideavimrc ~/.ideavimrc
ln -s ~/.dotfiles/.gitconfig ~/.gitconfig
ln -s ~/.dotfiles/.zshrc ~/.zshrc
ln -s ~/.dotfiles/.p10k.zsh ~/.p10k.zsh
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


echo "use ssh config?(y/n)"
read use_ssh_config
case $use_ssh_config in
    Y | y)
        echo "use ssh config" && ln -s ~/.dotfiles/.ssh/config ~/.ssh/config
esac

rm ~/.dotfiles/.vim/.vim
