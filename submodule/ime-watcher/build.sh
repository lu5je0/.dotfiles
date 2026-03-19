#!/bin/bash
set -e
cd "$(dirname "$0")"
clang -o ime_watcher_mac ime_watcher.c -framework CoreFoundation -framework Carbon
cp ime_watcher_mac /Users/lu5je0/.dotfiles/vim/lib/
