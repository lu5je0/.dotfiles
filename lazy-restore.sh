git checkout -- ~/.dotfiles/vim/lazy-lock.json
nvim --headless +":lua vim.cmd('LazyRestore') require('lazy').load({ plugins = { 'nvim-treesitter' }, opt = { force = true } }); vim.cmd('TSUpdateSync all')" +qa
