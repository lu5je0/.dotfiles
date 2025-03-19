cd $HOME/.dotfiles/build/neovim
make distclean
make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX=$HOME/.local/bin/nvim install
