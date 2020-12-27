c:
cd %HOMEPATH%
mklink /J %HOMEPATH%\vimfiles %HOMEPATH%\.dotfiles\.vim
mklink %HOMEPATH%\.ideavimrc %HOMEPATH%\.dotfiles\.ideavimrc
mklink %HOMEPATH%\.ssh\config %HOMEPATH%\.dotfiles\.ssh\config_win
