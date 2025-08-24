WIN_HOME=/mnt/c/Users/lu5je0

# wezterm
/mnt/c/Windows/System32/cmd.exe \
  /c sudo mklink /J \
  `wslpath -w $WIN_HOME/.config/wezterm` \
  `wslpath -w $WIN_HOME/.dotfiles/wezterm`

# gitconfig
/mnt/c/Windows/System32/cmd.exe \
  /c sudo mklink \
  `wslpath -w $WIN_HOME/.gitconfig` \
  `wslpath -w $WIN_HOME/.dotfiles/win/wsl2/gitconfig`

# wslconfig
/mnt/c/Windows/System32/cmd.exe \
  /c sudo mklink \
  `wslpath -w $WIN_HOME/.wslconfig` \
  `wslpath -w $WIN_HOME/.dotfiles/win/wsl2/wslconfig`
