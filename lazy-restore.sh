git checkout -- ~/.dotfiles/vim/lazy-lock.json
nvim --headless +":lua vim.cmd('LazyRestore'); require('lazy').load({ plugins = { 'nvim-treesitter' }, opt = { force = true } }); require('nvim-treesitter.install').update({}, { summary = true }):wait(300000)" +qa
