c:
cd %HOMEPATH%
mklink /J %HOMEPATH%\vimfiles %HOMEPATH%\.dotfiles\.vim
mklink /J %HOMEPATH%\AppData\Local\nvim %HOMEPATH%\.dotfiles\.vim
mklink %HOMEPATH%\AppData\Local\nvim\init.vim %HOMEPATH%\.dotfiles\.vim\vimrc
mklink %HOMEPATH%\.ideavimrc %HOMEPATH%\.dotfiles\.ideavimrc
mklink %HOMEPATH%\AppData\Local\nvim\init.vim %HOMEPATH%\.dotfiles\.vim\vimrc
mklink %HOMEPATH%\.ssh\config %HOMEPATH%\.dotfiles\.ssh\config_win
