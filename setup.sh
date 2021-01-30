ln -s ~/.dotfiles/.vim ~/.vim
ln -s ~/.dotfiles/.ideavimrc ~/.ideavimrc
ln -s ~/.dotfiles/.gitconfig ~/.gitconfig
ln -s ~/.dotfiles/.zshrc ~/.zshrc
ln -s ~/.dotfiles/.pip ~/.pip
ln -s ~/.dotfiles/.tmux.conf ~/.tmux.conf

# nvim
mkdir ~/.local/share/nvim
ln -s ~/.dotfiles/.vim ~/.local/share/nvim/site
mkdir -p ~/.config/nvim
ln -s ~/.dotfiles/.vim/vimrc ~/.config/nvim/init.vim
ln -s ~/.dotfiles/.vim/coc-settings.json ~/.config/nvim/coc-settings.json

cp ~/.dotfiles/zsh/lu5je0.zsh-theme ~/.oh-my-zsh/themes

ln -s ~/.dotfiles/.ssh/config ~/.ssh/config
rm ~/.dotfiles/.vim/.vim

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
