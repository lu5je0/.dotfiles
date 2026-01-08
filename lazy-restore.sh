#!/bin/bash

LAZY_DIR="$HOME/.local/share/nvim/lazy"
PLUGIN_LIST=(
    "LuaSnip"
)

for PLUGIN in "${PLUGIN_LIST[@]}"; do
    TARGET="${LAZY_DIR}/${PLUGIN}"
    if [ -d "$TARGET" ]; then
        # 进入目录并检测 git 状态
        STATUS=$(cd "$TARGET" && git status --porcelain)
        if [ -n "$STATUS" ]; then
            echo "Deleting $TARGET because git status is not empty."
            rm -rf "$TARGET"
        else
            echo "$TARGET is clean. Not deleting."
        fi
    fi
done

git checkout -- ~/.dotfiles/vim/lazy-lock.json
nvim --headless +":lua vim.cmd('LazyRestore'); require('lazy').load({ plugins = { 'nvim-treesitter' }, opt = { force = true } }); require('nvim-treesitter.install').update({}, { summary = true }):wait(300000)" +qa
