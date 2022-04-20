vim.g.do_filetype_lua = 1
vim.filetype.add {
  extension = {
    zsh = 'sh',
  },
  filename = {
    -- Set the filetype of files named "MyBackupFile" to lua
    ['.bashrc'] = 'sh',
    ['.zshrc'] = 'sh',
    ['zshrc'] = 'sh',
    ['bashrc'] = 'sh',
    ['.ohmyenv'] = 'sh',
    ['*tmux.conf'] = 'tmux',
    ['tmux.conf'] = 'tmux',
  },
  -- pattern = {
  --   [".*/etc/foo/.*%.conf"] = "foorc",
  -- },
}
