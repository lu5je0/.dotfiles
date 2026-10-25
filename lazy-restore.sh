#!/bin/bash

LAZY_DIR="$HOME/.local/share/nvim/lazy"
PLUGIN_LIST=(
    "LuaSnip",
    "lsp_signature.nvim"
    "blink.cmp"
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

# workaround: lazy-legacy-inplace-patches
# 临时兼容旧版 lazy patch：先撤销插件目录里的原地补丁，避免 Lazy restore 被本地 diff 阻塞。
# TODO: 所有环境都已切换到缓存副本补丁后，移除此兼容段。
PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/vim/patches"
LEGACY_PATCHES=(
    "glance.nvim:glance-nixd-definition.diff"
    "snacks.nvim:snacks-wezterm-placeholders.diff"
    "indent-blankline.nvim:indent-blankline.diff"
    "nvim-tree.lua:nvim-tree.diff"
)

for ENTRY in "${LEGACY_PATCHES[@]}"; do
    TARGET="${LAZY_DIR}/${ENTRY%%:*}"
    PATCH="${PATCH_DIR}/${ENTRY#*:}"
    if [ -e "$TARGET/.git" ] && [ -f "$PATCH" ]; then
        # 只移除可完整反向应用的已知补丁，保留其他本地修改；未打补丁时不操作。
        if git -C "$TARGET" apply --reverse --check "$PATCH" 2>/dev/null; then
            echo "Removing legacy patch ${ENTRY#*:} from $TARGET."
            git -C "$TARGET" apply --reverse "$PATCH" || exit 1
        fi
    fi
done

git checkout -- ~/.dotfiles/vim/lazy-lock.json
nvim --headless +":lua vim.cmd('Lazy! restore'); require('lazy').load({ plugins = { 'nvim-treesitter' }, opt = { force = true } }); require('nvim-treesitter.install').update({}, { summary = true }):wait(300000)" +qa
