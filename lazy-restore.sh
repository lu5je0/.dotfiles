git checkout -- ~/.dotfiles/vim/lazy-lock.json
nvim --headless +":lua vim.cmd('Lazy! restore') require('lazy').load({ plugins = { 'nvim-treesitter' }, opt = { force = true } }); vim.cmd('TSUpdateSync all')" +qa
