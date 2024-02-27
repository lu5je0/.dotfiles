git checkout -- ~/.dotfiles/vim/lazy-lock.json
nvim --headless +"Lazy! restore" +qa
nvim --headless +":lua require('lazy').load({ plugins = { 'nvim-treesitter' }, opt = { force = true } }); vim.cmd('TSUpdateSync all')" +qa
