vim.filetype.add {
  extension = {
    zsh = 'sh',
  },
  filename = {
    -- Set the filetype of files named "MyBackupFile" to lua
    ['.bashrc'] = 'bash',
    ['.zshrc'] = 'bash',
    ['zshrc'] = 'bash',
    ['bashrc'] = 'bash',
    ['.ohmyenv'] = 'bash',
    ['crontab'] = 'crontab',
    ['aria2.conf'] = 'dosini',
  },
  pattern = {
    ['.*%.tmux.conf'] = 'tmux',
  },
}
