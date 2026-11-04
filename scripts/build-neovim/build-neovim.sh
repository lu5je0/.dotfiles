cd $HOME/.dotfiles/build/neovim
rm $HOME/.local/bin/nvim -rf
make distclean
make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX=$HOME/.local/bin/nvim install
