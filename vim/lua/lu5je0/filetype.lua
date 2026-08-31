---@diagnostic disable: unused-local

vim.filetype.add {
  extension = {
    zip = 'zip',
    plantuml = 'plantuml',
    sh = 'bash',
    arthas = 'arthas',
    -- shebang 兜底：nvim 匹配不到 hashbang pattern 时会用解释器名回查 extension 表
    bun = 'typescript',
  },
  filename = {
    ['.bashrc'] = 'bash',
    ['.zshrc'] = 'bash',
    ['zshrc'] = 'bash',
    ['bashrc'] = 'bash',
    ['.ohmyenv'] = 'bash',
    ['crontab'] = 'crontab',
    ['kitty.conf'] = 'config',
    ['gitconfig'] = 'gitconfig',
    ['.wslconfig'] = 'dosini',
    ['wslconfig'] = 'dosini',
    ['requirements.txt'] = 'config',
  },
  pattern = {
    ['.*.tmux.conf'] = 'tmux',
    ['.*.zsh'] = 'bash',
    ['.*/ssh/config'] = 'sshconfig',
    ['.*/.ssh/config.d/.*'] = 'sshconfig',
    ['.*/git/config'] = 'gitconfig',
    ['.*/.dotfiles/services/.*'] = 'systemd',
    ['.*/.dotfiles/ghostty/config'] = 'config',
  },
}
