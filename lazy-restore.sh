#!/bin/bash

LAZY_DIR="$HOME/.local/share/nvim/lazy"
PLUGIN_LIST=(
    "LuaSnip"
)

for PLUGIN in "${PLUGIN_LIST[@]}"; do
    TARGET="${LAZY_DIR}/${PLUGIN}"
    if [ -d "$TARGET" ]; then
      rm $TARGET -rf
    fi
done

git checkout -- ~/.dotfiles/vim/lazy-lock.json
nvim --headless +":lua vim.cmd('LazyRestore'); require('lazy').load({ plugins = { 'nvim-treesitter' }, opt = { force = true } }); require('nvim-treesitter.install').update({}, { summary = true }):wait(300000)" +qa
