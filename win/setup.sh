WIN_HOME=/mnt/c/Users/lu5je0

# wezterm
/mnt/c/Windows/System32/cmd.exe \
  /c sudo mklink /d \
  `wslpath -w $WIN_HOME/.wezterm.lua` \
  `wslpath -w $WIN_HOME/.dotfiles/wezterm/wezterm.lua`

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
