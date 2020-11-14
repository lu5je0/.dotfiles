c:
cd %HOMEPATH%
mklink /J %HOMEPATH%\vimfiles %HOMEPATH%\.dotfiles\.vim
mklink /H %HOMEPATH%\.ideavimrc %HOMEPATH%\.dotfiles\.ideavimrc
mklink /H %HOMEPATH%\.ssh\config %HOMEPATH%\.dotfiles\.ssh\config_win
